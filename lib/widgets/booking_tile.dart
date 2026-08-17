import 'package:flutter/material.dart';

class BookingTile extends StatelessWidget {
  final String customerName;
  final String serviceName;
  final String time;
  final String status;
  final Color statusColor;
  final VoidCallback onTap;
  final String? barberName;
  final double? price;
  final String? imageUrl;
  final bool showActions;
  final VoidCallback? onComplete;
  
  // VIP and Queue parameters
  final bool isVip;
  final int? queueNumber;
  final String? queueToken;
  
  // Salon name parameter
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
    this.price,
    this.imageUrl,
    this.showActions = false,
    this.onComplete,
    this.isVip = false,
    this.queueNumber,
    this.queueToken,
    this.salonName,
  });

  @override
  Widget build(BuildContext context) {
    // ✅ Responsive sizing
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;
    
    final padding = isTablet ? 16.0 : 12.0;
    final avatarSize = isTablet ? 60.0 : 50.0;
    final nameSize = isTablet ? 18.0 : 16.0;
    final subSize = isTablet ? 14.0 : 13.0;
    final smallSize = isTablet ? 12.0 : 11.0;
    final priceSize = isTablet ? 16.0 : 14.0;
    final iconSize = isTablet ? 14.0 : 12.0;
    final borderRadius = isTablet ? 16.0 : 12.0;
    final minHeight = isTablet ? 100.0 : 80.0;

    return Card(
      margin: EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      color: Theme.of(context).cardColor, // ✅ Dark mode support
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        splashColor: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
        highlightColor: const Color(0xFFFF6B8B).withValues(alpha: 0.05),
        child: Container(
          constraints: BoxConstraints(
            minHeight: minHeight, // ✅ Minimum touch target
          ),
          padding: EdgeInsets.all(padding),
          child: Row(
            children: [
              // ✅ Responsive Profile Image
              Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                  image: imageUrl != null
                      ? DecorationImage(
                          image: NetworkImage(imageUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: imageUrl == null
                    ? Center(
                        child: Text(
                          customerName.isNotEmpty
                              ? customerName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontSize: avatarSize * 0.4,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFFF6B8B),
                          ),
                        ),
                      )
                    : null,
              ),
              SizedBox(width: padding),

              // Booking Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Customer Name Row with VIP Badge
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            customerName,
                            style: TextStyle(
                              fontSize: nameSize,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).textTheme.bodyLarge?.color,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // VIP Badge
                        if (isVip)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Colors.amber, Colors.orange],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.star,
                                  size: 10,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
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

                    // Salon Name
                    if (salonName != null && salonName!.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.store,
                            size: iconSize,
                            color: Colors.blue[600],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              salonName!,
                              style: TextStyle(
                                fontSize: subSize * 0.9,
                                color: Colors.blue[700],
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                    ],

                    // Service and Barber
                    Row(
                      children: [
                        Icon(
                          Icons.content_cut,
                          size: iconSize,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            serviceName,
                            style: TextStyle(
                              fontSize: subSize,
                              color: Colors.grey[600],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (barberName != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: iconSize,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            barberName!,
                            style: TextStyle(
                              fontSize: subSize,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],

                    // Time, Queue Number and Status
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        // Time
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.access_time,
                                size: smallSize,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                time,
                                style: TextStyle(
                                  fontSize: smallSize,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // Queue Number / Token
                        if (queueNumber != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.blue.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.numbers,
                                  size: smallSize,
                                  color: Colors.blue[700],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Q-$queueNumber',
                                  style: TextStyle(
                                    fontSize: smallSize,
                                    color: Colors.blue[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                        if (queueToken != null && queueNumber == null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.blue.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.qr_code,
                                  size: smallSize,
                                  color: Colors.blue[700],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  queueToken!,
                                  style: TextStyle(
                                    fontSize: smallSize,
                                    color: Colors.blue[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Status
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              fontSize: smallSize,
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Price Row
                    if (price != null)
                      Text(
                        'Rs. ${price!.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: priceSize,
                          fontWeight: FontWeight.w600,
                          color: Colors.green[700],
                        ),
                      ),

                    // Action buttons if showActions is true
                    if (showActions && onComplete != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Complete button - Responsive
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
                                borderRadius: BorderRadius.circular(
                                  isTablet ? 10 : 8,
                                ),
                              ),
                              textStyle: TextStyle(
                                fontSize: isTablet ? 15 : 13,
                              ),
                            ),
                            child: const Text('Complete'),
                          ),
                          const SizedBox(width: 8),
                          // Reschedule button - Responsive
                          OutlinedButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Reschedule feature coming soon'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.orange,
                              side: const BorderSide(color: Colors.orange),
                              minimumSize: Size(
                                isTablet ? 120 : 100,
                                isTablet ? 44 : 36,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  isTablet ? 10 : 8,
                                ),
                              ),
                              textStyle: TextStyle(
                                fontSize: isTablet ? 15 : 13,
                              ),
                            ),
                            child: const Text('Reschedule'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Arrow icon - hide when actions are shown
              if (!showActions)
                Icon(
                  Icons.arrow_forward_ios,
                  size: isTablet ? 16 : 14,
                  color: Colors.grey[400],
                ),
            ],
          ),
        ),
      ),
    );
  }
}