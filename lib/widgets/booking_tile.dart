import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

class BookingTile extends StatelessWidget {
  final String customerName;
  final String serviceName;
  final String time;
  final String status;
  final Color statusColor;
  final VoidCallback onTap;
  final String? barberName;

  // Price is a pre-formatted string (multi-currency safe)
  // e.g. CurrencyService.instance.format(price: p, currencyCode: code)
  final String? formattedPrice;

  final String? imageUrl;
  final bool showActions;
  final VoidCallback? onComplete;

  /// Label of the green button (default 'Complete'). Use 'End' for in-progress ones.
  final String completeLabel;

  /// The Reschedule button is shown only when this is given
  /// (the old "coming soon" placeholder is gone).
  final VoidCallback? onReschedule;

  // VIP and Queue
  final bool isVip;
  final int? queueNumber;
  final String? queueToken;

  /// Ready-made queue text, e.g. 'VIP-3' or 'Q5'. Wins over [queueNumber].
  final String? queueLabel;

  /// 'paid' | 'partial' | 'unpaid' | 'refunded' | null
  /// Pass null for cancelled / no-show bookings (no payment chip is shown).
  final String? paymentStatus;

  final String? salonName;

  const BookingTile({
    super.key,
    required this.customerName,
    required this.serviceName,
    required this.time,
    required this.status,
    required this.statusColor,
    required this.onTap,
    this.barberName,
    this.formattedPrice,
    this.imageUrl,
    this.showActions = false,
    this.onComplete,
    this.completeLabel = 'Complete',
    this.onReschedule,
    this.isVip = false,
    this.queueNumber,
    this.queueToken,
    this.queueLabel,
    this.paymentStatus,
    this.salonName,
  });

  static const Color _brand = Color(0xFFFF6B8B);

  Widget _chip(String text, Color color, {IconData? icon, bool outlined = true}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: outlined
            ? Border.all(color: color.withValues(alpha: 0.35))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget? _paymentChip() {
    switch (paymentStatus) {
      case 'paid':
        return _chip('PAID', Colors.green.shade700, icon: Icons.check_circle);
      case 'partial':
        return _chip('PARTIAL', Colors.orange.shade800, icon: Icons.timelapse);
      case 'refunded':
        return _chip('REFUND', Colors.red.shade600, icon: Icons.undo);
      case 'unpaid':
        return _chip('UNPAID', Colors.grey.shade600, icon: Icons.schedule);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;
    final isDark = context.isDarkMode;

    final padding = isTablet ? 16.0 : 12.0;
    final avatarSize = isTablet ? 60.0 : 50.0;
    final nameSize = isTablet ? 18.0 : 16.0;
    final subSize = isTablet ? 14.0 : 13.0;
    final smallSize = isTablet ? 12.0 : 11.0;
    final priceSize = isTablet ? 16.0 : 14.0;
    final iconSize = isTablet ? 14.0 : 12.0;
    final borderRadius = isTablet ? 16.0 : 12.0;
    final minHeight = isTablet ? 100.0 : 80.0;

    final muted = isDark ? Colors.grey[400] : Colors.grey[600];
    final blue = isDark ? Colors.blue[300]! : Colors.blue[700]!;

    final qText = (queueLabel != null && queueLabel!.isNotEmpty)
        ? queueLabel
        : (queueNumber != null ? (isVip ? 'VIP-$queueNumber' : 'Q-$queueNumber') : null);
    final payChip = _paymentChip();

    final avatarLetter = Center(
      child: Text(
        customerName.isNotEmpty ? customerName[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: avatarSize * 0.4,
          fontWeight: FontWeight.bold,
          color: _brand,
        ),
      ),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        splashColor: _brand.withValues(alpha: 0.1),
        highlightColor: _brand.withValues(alpha: 0.05),
        child: Container(
          constraints: BoxConstraints(minHeight: minHeight),
          padding: EdgeInsets.all(padding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile image (cached, falls back to the first letter)
              Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _brand.withValues(alpha: 0.1),
                ),
                child: (imageUrl != null && imageUrl!.isNotEmpty)
                    ? ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: imageUrl!,
                          width: avatarSize,
                          height: avatarSize,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => avatarLetter,
                        ),
                      )
                    : avatarLetter,
              ),
              SizedBox(width: padding),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name + VIP
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            customerName,
                            style: TextStyle(
                              fontSize: nameSize,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        if (isVip)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            margin: const EdgeInsets.only(left: 6),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Colors.amber, Colors.orange],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star, size: 8, color: Colors.white),
                                const SizedBox(width: 2),
                                Text(
                                  'VIP',
                                  style: TextStyle(
                                    fontSize: smallSize * 0.8,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    if (salonName != null && salonName!.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(Icons.store, size: iconSize, color: blue),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              salonName!,
                              style: TextStyle(
                                fontSize: subSize * 0.9,
                                color: blue,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                    ],

                    Row(
                      children: [
                        Icon(Icons.content_cut, size: iconSize, color: muted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            serviceName,
                            style: TextStyle(fontSize: subSize, color: muted),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                    if (barberName != null && barberName!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.person_outline, size: iconSize, color: muted),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              barberName!,
                              style: TextStyle(fontSize: subSize, color: muted),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ],

                    // Time, queue, status, payment
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.access_time, size: smallSize, color: muted),
                              const SizedBox(width: 4),
                              Text(
                                time,
                                style: TextStyle(fontSize: smallSize, color: muted),
                              ),
                            ],
                          ),
                        ),
                        if (qText != null)
                          _chip(
                            qText,
                            isVip ? Colors.amber.shade700 : Colors.blue.shade600,
                            icon: isVip ? Icons.star : Icons.numbers,
                          )
                        else if (queueToken != null && queueToken!.isNotEmpty)
                          _chip(queueToken!, Colors.blue.shade600, icon: Icons.qr_code),
                        _chip(status, statusColor, outlined: false),
                        ?payChip,
                      ],
                    ),

                    if (formattedPrice != null && formattedPrice!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        formattedPrice!,
                        style: TextStyle(
                          fontSize: priceSize,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.green[300] : Colors.green[700],
                        ),
                      ),
                    ],

                    // Action buttons
                    if (showActions && onComplete != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton(
                            onPressed: onComplete,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              minimumSize: Size(
                                isTablet ? 120 : 100,
                                isTablet ? 44 : 36,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(isTablet ? 10 : 8),
                              ),
                              textStyle: TextStyle(fontSize: isTablet ? 15 : 13),
                            ),
                            child: Text(completeLabel),
                          ),
                          if (onReschedule != null) ...[
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: onReschedule,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.orange,
                                side: const BorderSide(color: Colors.orange),
                                minimumSize: Size(
                                  isTablet ? 120 : 100,
                                  isTablet ? 44 : 36,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(isTablet ? 10 : 8),
                                ),
                                textStyle: TextStyle(fontSize: isTablet ? 15 : 13),
                              ),
                              child: const Text('Reschedule'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              if (!showActions)
                Icon(
                  Icons.arrow_forward_ios,
                  size: isTablet ? 16 : 14,
                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                ),
            ],
          ),
        ),
      ),
    );
  }
}