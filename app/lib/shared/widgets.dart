import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Kartu darurat: satu-satunya tempat warna merah dipakai. Menggantikan alur obrolan biasa.
class EmergencyCard extends StatelessWidget {
  const EmergencyCard({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Tanda bahaya',
      child: Container(
        key: const Key('emergency_card'),
        padding: const EdgeInsets.all(KiraSpace.lg),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(KiraRadius.card),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.emergency_outlined, color: scheme.onErrorContainer),
            const SizedBox(width: KiraSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tanda bahaya', style: context.text.titleMedium?.copyWith(color: scheme.onErrorContainer)),
                  const SizedBox(height: KiraSpace.xs),
                  Text(message, style: context.text.bodyLarge?.copyWith(color: scheme.onErrorContainer)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kotak informasi lembut untuk status kosong, catatan, atau penjelasan.
class SoftNote extends StatelessWidget {
  const SoftNote({super.key, required this.icon, required this.text, this.title});
  final IconData icon;
  final String text;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KiraSpace.lg),
      decoration: BoxDecoration(
        color: context.scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(KiraRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: context.scheme.onSurfaceVariant),
          const SizedBox(width: KiraSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) Text(title!, style: context.text.titleSmall),
                Text(text, style: context.text.bodyMedium?.copyWith(color: context.scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Gelembung percakapan, dipakai bersama oleh chat dan onboarding.
class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.text, required this.mine});
  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(KiraRadius.card),
      topRight: const Radius.circular(KiraRadius.card),
      bottomLeft: Radius.circular(mine ? KiraRadius.card : 6),
      bottomRight: Radius.circular(mine ? 6 : KiraRadius.card),
    );
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: KiraSpace.lg, vertical: KiraSpace.md),
          decoration: BoxDecoration(
            color: mine ? scheme.primaryContainer : scheme.surfaceContainerLowest,
            borderRadius: radius,
            border: mine ? null : Border.all(color: scheme.outlineVariant),
          ),
          child: Text(
            text,
            style: context.text.bodyLarge?.copyWith(color: mine ? scheme.onPrimaryContainer : scheme.onSurface),
          ),
        ),
      ),
    );
  }
}

