import 'package:flutter/material.dart';

/// A small coloured pill for an order status or similar label.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final Color color;
    switch (status) {
      case 'confirmed':
        color = dark ? const Color(0xFF5FD39A) : const Color(0xFF18794E);
      case 'pending':
        color = dark ? const Color(0xFFE8B15A) : const Color(0xFFA15C08);
      case 'cancelled':
        color = dark ? const Color(0xFFFF8A8A) : const Color(0xFFB4232F);
      default:
        color = Theme.of(context).colorScheme.onSurfaceVariant;
    }
    final text = status.isEmpty
        ? ''
        : status[0].toUpperCase() + status.substring(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
