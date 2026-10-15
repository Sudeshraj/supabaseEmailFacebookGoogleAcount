import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum PlayEventType { verified, pending, canceled, error }

class PlayPurchaseEvent {
  final PlayEventType type;
  final String? productId;
  final String? message;
  const PlayPurchaseEvent(this.type, {this.productId, this.message});
}

class PlayVerifyResult {
  final bool success;
  final bool entitled;
  final String? planName;
  final String? message;
  const PlayVerifyResult({
    required this.success,
    this.entitled = false,
    this.planName,
    this.message,
  });
}

/// Google Play Billing for the Android app.
///
/// The app NEVER decides who has a plan. Every purchase is sent to the
/// `play-billing-verify` Edge Function, which asks Google, checks that the
/// purchase was made by this logged-in user, stores it and acknowledges it.
/// Only after that succeeds do we call completePurchase().
class PlayBillingService {
  PlayBillingService._();
  static final PlayBillingService instance = PlayBillingService._();

  /// Google Play subscriptions screen (cancel / change payment method there)
  static final Uri manageUri = Uri.parse(
    'https://play.google.com/store/account/subscriptions',
  );

  /// Only the Android app uses Google Play Billing
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final InAppPurchase _iap = InAppPurchase.instance;
  final StreamController<PlayPurchaseEvent> _events =
      StreamController<PlayPurchaseEvent>.broadcast();

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  bool _started = false;

  Stream<PlayPurchaseEvent> get events => _events.stream;

  SupabaseClient get _supabase => Supabase.instance.client;

  /// Safe to call many times. Does nothing unless a user is logged in.
  Future<void> start() async {
    if (!isSupported || _started) return;
    if (_supabase.auth.currentUser == null) return;

    final available = await _iap.isAvailable();
    if (!available) {
      debugPrint('⚠️ Google Play Billing is not available on this device');
      return;
    }

    _started = true;
    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) => debugPrint('❌ purchaseStream error: $e'),
    );

    // Re-check everything Google says this account owns
    unawaited(syncOwned());
  }

  /// Call on sign-out
  Future<void> stop() async {
    await _purchaseSub?.cancel();
    _purchaseSub = null;
    _started = false;
  }

  // ------------------------------------------------------------
  // Products
  // ------------------------------------------------------------

  /// productId -> Google Play product details (price is already localised)
  Future<Map<String, GooglePlayProductDetails>> loadProducts(
    Set<String> productIds,
  ) async {
    if (!isSupported || productIds.isEmpty) return {};
    final response = await _iap.queryProductDetails(productIds);
    if (response.error != null) {
      debugPrint('❌ queryProductDetails: ${response.error!.message}');
    }
    final result = <String, GooglePlayProductDetails>{};
    for (final p in response.productDetails) {
      if (p is GooglePlayProductDetails) {
        result.putIfAbsent(p.id, () => p);
      }
    }
    return result;
  }

  /// The user's current Google Play subscription (needed to switch plans)
  Future<GooglePlayPurchaseDetails?> findCurrentPurchase(
    Set<String> productIds,
  ) async {
    if (!isSupported) return null;
    final addition = _iap
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final response = await addition.queryPastPurchases();
    if (response.error != null) return null;
    for (final p in response.pastPurchases) {
      if (productIds.contains(p.productID) &&
          p.status == PurchaseStatus.purchased) {
        return p;
      }
    }
    return null;
  }

  // ------------------------------------------------------------
  // Buy / switch plan
  // ------------------------------------------------------------

  /// Opens the Google Play purchase sheet. The RESULT arrives through
  /// [events] (verified / pending / canceled / error).
  ///
  /// [oldPurchase] != null  -> plan switch:
  ///    upgrade   -> charged now, prorated for the unused time
  ///    downgrade ([deferred] = true) -> starts at the next renewal
  Future<bool> buy({
    required GooglePlayProductDetails product,
    required String ownerId,
    GooglePlayPurchaseDetails? oldPurchase,
    bool deferred = false,
  }) async {
    final param = GooglePlayPurchaseParam(
      productDetails: product,
      // becomes the obfuscated account id: the server checks it equals the
      // logged-in user, so nobody can claim someone else's purchase
      applicationUserName: ownerId,
      changeSubscriptionParam: oldPurchase == null
          ? null
          : ChangeSubscriptionParam(
              oldPurchaseDetails: oldPurchase,
              replacementMode: deferred
                  ? ReplacementMode.deferred
                  : ReplacementMode.chargeProratedPrice,
            ),
    );
    return _iap.buyNonConsumable(purchaseParam: param);
  }

  // ------------------------------------------------------------
  // Purchase stream
  // ------------------------------------------------------------

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          _events.add(
            PlayPurchaseEvent(PlayEventType.pending, productId: p.productID),
          );
          break;
        case PurchaseStatus.canceled:
          _events.add(
            PlayPurchaseEvent(PlayEventType.canceled, productId: p.productID),
          );
          break;
        case PurchaseStatus.error:
          _events.add(
            PlayPurchaseEvent(
              PlayEventType.error,
              productId: p.productID,
              message: p.error?.message,
            ),
          );
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verifyAndComplete(p);
          break;
      }
    }
  }

  Future<void> _verifyAndComplete(PurchaseDetails p) async {
    final token = p.verificationData.serverVerificationData;
    final result = await verifyToken(token);

    if (result.success && result.entitled) {
      if (p.pendingCompletePurchase) {
        try {
          await _iap.completePurchase(p);
        } catch (e) {
          // the server already acknowledged it; harmless
          debugPrint('completePurchase: $e');
        }
      }
      _events.add(
        PlayPurchaseEvent(PlayEventType.verified, productId: p.productID),
      );
    } else {
      // NOT completed on purpose: Google keeps the purchase pending and
      // delivers it again next time, so we can retry.
      _events.add(
        PlayPurchaseEvent(
          PlayEventType.error,
          productId: p.productID,
          message: result.message ?? 'Could not verify the purchase',
        ),
      );
    }
  }

  /// Verify everything this Google account owns (app start / restore)
  Future<void> syncOwned() async {
    if (!isSupported) return;
    try {
      final addition = _iap
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final response = await addition.queryPastPurchases();
      if (response.error != null) return;
      for (final p in response.pastPurchases) {
        if (p.status == PurchaseStatus.purchased) {
          await _verifyAndComplete(p);
        }
      }
    } catch (e) {
      debugPrint('❌ syncOwned: $e');
    }
  }

  // ------------------------------------------------------------
  // Server verification
  // ------------------------------------------------------------

  Future<PlayVerifyResult> verifyToken(String purchaseToken) async {
    try {
      final response = await _supabase.functions.invoke(
        'play-billing-verify',
        body: {'purchase_token': purchaseToken},
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      return PlayVerifyResult(
        success: data['success'] == true,
        entitled: data['entitled'] == true,
        planName: data['plan_name'] as String?,
        message: data['message'] as String?,
      );
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map
          ? (details['message'] ?? details['error'])?.toString()
          : details?.toString();
      debugPrint('❌ play-billing-verify: status=${e.status}, $message');
      return PlayVerifyResult(success: false, message: message);
    } catch (e) {
      debugPrint('❌ play-billing-verify: $e');
      return PlayVerifyResult(success: false, message: e.toString());
    }
  }
}