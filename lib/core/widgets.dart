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

/// Press-and-hold SOS button — requires a genuine 2.5s hold before
/// firing. Uses onTapDown/onTapUp/onTapCancel — reliable across
/// mouse, trackpad, and touch input.
class SosButton extends StatefulWidget {
  final VoidCallback onTriggered;
  const SosButton({required this.onTriggered, super.key});

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500));
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onTriggered();
        _controller.reset();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: AppColors.sos,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: _controller.value,
                child: Container(
                  decoration: BoxDecoration(color: AppColors.sosPressed, borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning_rounded, color: Colors.white, size: 26),
                SizedBox(width: 10),
                Text('HOLD FOR SOS', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ],
            ),
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
/// consistent app bar with the AI Assistant icon always present.
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
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: AppColors.gold),
            tooltip: 'AI Assistant',
            onPressed: onAssistantTap,
          ),
          if (onLogout != null)
            IconButton(icon: const Icon(Icons.logout), onPressed: onLogout),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: body),
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