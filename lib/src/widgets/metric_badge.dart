import 'package:flutter/material.dart';

/// Componente visual para exibir uma métrica com rótulo, valor e cor.
class MetricBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final Color? labelColor;
  final double fontSize;

  const MetricBadge({
    super.key,
    required this.label,
    required this.value,
    required this.valueColor,
    this.labelColor,
    this.fontSize = 11.0,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: fontSize,
            fontFamily: 'monospace',
            height: 1.2,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: labelColor ?? Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: valueColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
