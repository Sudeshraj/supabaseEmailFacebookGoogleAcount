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
  final VoidCallback? onComplete;  // 👈 Add this line

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
    this.onComplete,  // 👈 Add this line
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Profile Image / Initial
              Container(
                width: 50,
                height: 50,
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
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFF6B8B),
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),

              // Booking Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Customer Name
                    Text(
                      customerName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Service and Barber
                    Row(
                      children: [
                        Icon(
                          Icons.content_cut,
                          size: 12,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            serviceName,
                            style: TextStyle(
                              fontSize: 13,
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
                            size: 12,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            barberName!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],

                    // Time and Status
                    const SizedBox(height: 8),
                    Row(
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
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 10,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                time,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

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
                              fontSize: 11,
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),

                        const Spacer(),

                        // Price if available
                        if (price != null)
                          Text(
                            'Rs. ${price!.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.green[700],
                            ),
                          ),
                      ],
                    ),

                    // 👇 Add action buttons if showActions is true and onComplete exists
                    if (showActions && onComplete != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Complete button
                          ElevatedButton(
                            onPressed: onComplete,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(100, 36),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Complete'),
                          ),
                          const SizedBox(width: 8),
                          // Reschedule button
                          OutlinedButton(
                            onPressed: () {
                              // Handle reschedule
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
                              minimumSize: const Size(100, 36),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
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
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: Colors.grey,
                ),
            ],
          ),
        ),
      ),
    );
  }
}