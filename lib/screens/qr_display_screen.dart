import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/theme.dart';

class QrDisplayScreen extends StatelessWidget {
  final String groupCode;
  const QrDisplayScreen({required this.groupCode, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('Group QR Code')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: QrImageView(
                data: groupCode,
                version: QrVersions.auto,
                size: 240,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Text(groupCode, style: const TextStyle(color: AppColors.gold, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 4)),
            const SizedBox(height: 8),
            const Text('Tourists can scan this to join your group', style: AppTextStyles.subheading),
          ],
        ),
      ),
    );
  }
}