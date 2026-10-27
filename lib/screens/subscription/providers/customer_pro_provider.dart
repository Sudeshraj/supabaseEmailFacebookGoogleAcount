import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/customer_pro_service.dart';
import '../services/play_billing_service.dart';

/// Customer Pro membership. Use it ONLY in customer screens. Owner features
/// keep using SubscriptionProvider: the two never affect each other.
class CustomerProProvider extends ChangeNotifier {
  final CustomerProService _service = CustomerProService();

  CustomerProStatus? _status;
  bool _loading = false;
  String? _error;
  StreamSubscription<PlayPurchaseEvent>? _playSub;

  CustomerProStatus? get status => _status;
  bool get loading => _loading;
  String? get error => _error;

  /// true once the status has really been loaded
  bool get isReady => _status != null;

  /// Is the logged-in customer a Pro member right now?
  bool get isPro => _status?.isPro ?? false;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    final result = await _service.getMyStatus();
    if (result == null) {
      _error = 'Could not load your membership';
    } else {
      _status = result;
    }

    _loading = false;
    notifyListeners();

    _ensurePlayBilling();
  }

  Future<void> refresh() => load();

  /// Android: Google Play purchases can finish outside the screen (a delayed
  /// payment, a renewal...). Refresh whenever one is verified by the server.
  void _ensurePlayBilling() {
    if (!PlayBillingService.isSupported) return;
    _playSub ??= PlayBillingService.instance.events.listen((event) {
      if (event.type == PlayEventType.verified) load();
    });
    PlayBillingService.instance.start();
  }

  /// Call on logout
  void clear() {
    _status = null;
    _error = null;
    _loading = false;
    _playSub?.cancel();
    _playSub = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _playSub?.cancel();
    super.dispose();
  }
}