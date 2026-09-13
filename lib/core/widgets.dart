import 'package:flutter/material.dart';
import 'theme.dart';

/// A solid navy card — the standard container for grouped content.
class NavyCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const NavyCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.navyCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.navyBorder, width: 1),
      ),
      child: child,
    );
  }
}

/// One-tap SOS with an instant confirmation dialog — fast, but with
/// a quick safety check so a stray tap can't fire it silently.
class SosButton extends StatelessWidget {
  final VoidCallback onTriggered;
  const SosButton({required this.onTriggered, super.key});

  Future<void> _handleTap(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.navyCard,
        title: const Text('Send SOS?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will alert your guide, emergency contact, and nearest group member with your location.',
          style: TextStyle(color: AppColors.textOnNavySecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send SOS', style: TextStyle(color: AppColors.sos, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed == true) onTriggered();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _handleTap(context),
      child: Container(
        height: 64,
        decoration: BoxDecoration(color: AppColors.sos, borderRadius: BorderRadius.circular(16)),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_rounded, color: Colors.white, size: 26),
            SizedBox(width: 10),
            Text('TAP FOR SOS', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

/// Medical Aid — single tap + confirmation, lighter urgency than SOS.
class MedicalAidButton extends StatelessWidget {
  final VoidCallback onConfirmed;
  const MedicalAidButton({required this.onConfirmed, super.key});

  Future<void> _handleTap(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.navyCard,
        title: const Text('Request medical assistance?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Your guide and the nearest group member will be notified you may need help.',
          style: TextStyle(color: AppColors.textOnNavySecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Request Help')),
        ],
      ),
    );
    if (confirmed == true) onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _handleTap(context),
      child: Container(
        height: 44,
        decoration: BoxDecoration(color: AppColors.medical, borderRadius: BorderRadius.circular(12)),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.medical_services_outlined, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Feeling unwell? Tap for medical aid', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// Wraps any screen with the persistent emergency action bar and a
/// floating AI Assistant button, positioned so it never overlaps the
/// Medical Aid / SOS stack.
class AppScaffoldWithSos extends StatelessWidget {
  final Widget body;
  final String title;
  final Widget? drawer;
  final VoidCallback onSosTriggered;
  final VoidCallback onMedicalAidTriggered;
  final VoidCallback onAssistantTap;
  final VoidCallback? onLogout;

  const AppScaffoldWithSos({
    required this.body,
    required this.title,
    required this.onSosTriggered,
    required this.onMedicalAidTriggered,
    required this.onAssistantTap,
    this.drawer,
    this.onLogout,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: drawer,
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (onLogout != null)
            IconButton(icon: const Icon(Icons.logout), onPressed: onLogout),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: body),
          Positioned(
            right: 16,
            bottom: 190,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAssistantTap,
              child: Container(
                width: 54, height: 54,
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: const Icon(Icons.auto_awesome, color: AppColors.navyDark, size: 26),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MedicalAidButton(onConfirmed: onMedicalAidTriggered),
                const SizedBox(height: 10),
                SosButton(onTriggered: onSosTriggered),
              ],
            ),
          ),
        ],
      ),
    );
  }
}