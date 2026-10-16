import 'dart:typed_data';

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

/// Catatan kecil untuk penjelasan atau privasi: ikon dan teks tanpa kotak tebal, supaya tidak bersaing dengan isi.
class SoftNote extends StatelessWidget {
  const SoftNote({super.key, required this.icon, required this.text, this.title});
  final IconData icon;
  final String text;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: KiraSpace.md, vertical: KiraSpace.md),
      decoration: BoxDecoration(
        color: context.scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(KiraRadius.field),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: context.scheme.primary),
          const SizedBox(width: KiraSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: context.text.titleSmall),
                  const SizedBox(height: 2),
                ],
                Text(text, style: context.text.bodySmall?.copyWith(color: context.scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Judul kelompok di luar kartu, memberi hierarki pada halaman panjang.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(KiraSpace.xs, KiraSpace.xl, KiraSpace.xs, KiraSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: context.text.titleLarge),
              if (subtitle != null) Text(subtitle!, style: context.text.bodySmall),
            ]),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Status kosong: maskot KIRA, satu kalimat, dan (bila ada) satu langkah berikutnya.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.message, this.action});
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KiraSpace.lg, vertical: KiraSpace.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: 0.9,
            child: Image.asset('assets/icon/icon.png', width: 72, height: 72, excludeFromSemantics: true),
          ),
          const SizedBox(height: KiraSpace.lg),
          Text(title, textAlign: TextAlign.center, style: context.text.titleMedium),
          const SizedBox(height: KiraSpace.xs),
          Text(message, textAlign: TextAlign.center, style: context.text.bodyMedium?.copyWith(color: context.scheme.onSurfaceVariant)),
          if (action != null) ...[
            const SizedBox(height: KiraSpace.lg),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Tautan kecil "Sumber" yang membuka rujukannya di lembar bawah: rujukan tetap bisa dibaca tanpa memenuhi layar.
class SourceLink extends StatelessWidget {
  const SourceLink(this.source, {super.key, this.label = 'Sumber'});
  final String source;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: KiraSpace.sm),
        minimumSize: const Size(0, 36),
        textStyle: context.text.labelMedium,
        foregroundColor: context.scheme.onSurfaceVariant,
      ),
      icon: const Icon(Icons.menu_book_outlined, size: 16),
      label: Text(label),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(KiraSpace.xl, 0, KiraSpace.xl, KiraSpace.xl),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: ctx.text.titleMedium),
              const SizedBox(height: KiraSpace.sm),
              Text(source, style: ctx.text.bodyMedium),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Kumpulan tautan utilitas dalam satu kartu, dipisah garis tipis.
class LinkGroup extends StatelessWidget {
  const LinkGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 1, indent: 56, color: context.scheme.outlineVariant.withValues(alpha: 0.5)),
          children[i],
        ],
      ]),
    );
  }
}

/// Gelembung percakapan, dipakai bersama oleh chat dan onboarding.
class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.text, required this.mine, this.image});
  final String text;
  final bool mine;

  /// Foto yang dikirim pengguna. Bila ada, gelembung hanya berisi foto; teks menjadi label untuk pembaca layar.
  final Uint8List? image;

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
        child: image != null
            ? Semantics(
                image: true,
                label: text,
                child: ClipRRect(
                  borderRadius: radius,
                  child: Image.memory(
                    image!,
                    key: const Key('chat_photo'),
                    width: 240,
                    height: 240,
                    fit: BoxFit.cover,
                    cacheWidth: 720,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                    errorBuilder: (_, _, _) => ChatBubble(text: text, mine: mine),
                  ),
                ),
              )
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: KiraSpace.lg, vertical: KiraSpace.md),
                decoration: BoxDecoration(
                  color: mine ? scheme.primaryContainer : scheme.surfaceContainerLowest,
                  borderRadius: radius,
                  border: mine ? null : Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
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


/// Status gagal memuat: pesan ramah + tombol coba lagi (tanpa tampilan bernada menyalahkan).
class LoadError extends StatelessWidget {
  const LoadError({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KiraSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 40, color: context.scheme.onSurfaceVariant),
            const SizedBox(height: KiraSpace.md),
            Text(message, textAlign: TextAlign.center, style: context.text.bodyLarge),
            const SizedBox(height: KiraSpace.lg),
            FilledButton.tonal(key: const Key('retry_button'), onPressed: onRetry, child: const Text('Coba lagi')),
          ],
        ),
      ),
    );
  }
}

String friendlyError(Object error) => error.toString().contains('ApiException') || error is Exception
    ? error.toString()
    : 'Ada kendala saat memuat. Coba lagi sebentar lagi ya.';
