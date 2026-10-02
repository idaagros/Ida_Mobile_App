// lib/widgets/offline_notice.dart
//
// Shared pieces for a screen that can save without signal (offline entry,
// Oct 2026). Same look as the attendance screen's notice.
//
//   OfflineNotice(queueKey: 'electricity:2026-10-01')
//       -> shows "waiting to send" or "Not sent: <reason>" while an entry
//          with that key is on the phone; nothing otherwise.
//   OfflineNotice.savedSnack(context)
//       -> the amber "Saved on this phone ..." message after a save that
//          came back as queued (Api.wasQueued(res)).
import 'package:flutter/material.dart';
import '../localization/app_localizations.dart';
import '../services/offline_queue.dart';

class OfflineNotice extends StatelessWidget {
  final String queueKey;
  const OfflineNotice({super.key, required this.queueKey});

  static void savedSnack(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(loc.offSavedSnack),
      backgroundColor: const Color(0xFFB45309),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: Listenable.merge([Offline.sentTick, Offline.pendingCount, Offline.failedCount]),
      builder: (context, _) {
        final e = Offline.waitingFor(queueKey);
        if (e == null) return const SizedBox.shrink();
        final failed = e.status == 'failed';
        final fg = failed ? const Color(0xFFC0392B) : const Color(0xFF92600A);
        final bg = failed ? const Color(0xFFFDE8E8) : const Color(0xFFFEF3DC);
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(failed ? Icons.error_outline : Icons.cloud_upload_outlined, color: fg, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(failed ? loc.offNoticeFailed(e.error) : loc.offNoticeWaiting,
                    style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ]),
            if (failed) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/offline'),
                  style: TextButton.styleFrom(foregroundColor: fg, padding: const EdgeInsets.symmetric(horizontal: 8)),
                  child: Text(loc.offOpenList, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ]),
        );
      },
    );
  }
}
