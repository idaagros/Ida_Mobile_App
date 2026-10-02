// lib/screens/offline_queue_screen.dart
//
// "Waiting to send / Not sent": every entry saved on this phone for the
// signed-in person that the server has not taken yet.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../localization/app_localizations.dart';
import '../services/offline_queue.dart';
import '../services/responsive.dart';

class OfflineQueueScreen extends StatefulWidget {
  const OfflineQueueScreen({super.key});
  @override
  State<OfflineQueueScreen> createState() => _OfflineQueueScreenState();
}

class _OfflineQueueScreenState extends State<OfflineQueueScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);

  late final Listenable _changes = Listenable.merge([
    Offline.sentTick,
    Offline.pendingCount,
    Offline.failedCount,
  ]);

  Future<void> _refresh() async {
    try {
      await Offline.flush();
    } catch (_) {}
  }

  Future<void> _discard(OfflineEntry e) async {
    final loc = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(loc.offDiscardTitle,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        content: Text(loc.offDiscardBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  Text(loc.cancel, style: const TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC0392B)),
            child: Text(loc.offDiscard,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) await Offline.discard(e.id);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(loc.offQueueTitle,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: ListenableBuilder(
        listenable: _changes,
        builder: (context, _) {
          final items = Offline.mine();
          return RefreshIndicator(
            color: idaGreen,
            onRefresh: _refresh,
            child: Responsive.constrainedContent(
              context,
              ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E2),
                        borderRadius: BorderRadius.circular(12)),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline,
                              color: idaGreen, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(loc.offInfo,
                                  style: const TextStyle(
                                      color: idaDark,
                                      fontSize: 12.5,
                                      height: 1.35))),
                        ]),
                  ),
                  const SizedBox(height: 14),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: Text(loc.offEmpty,
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 14)),
                      ),
                    )
                  else
                    for (final e in items) _card(loc, e),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _card(AppLocalizations loc, OfflineEntry e) {
    final failed = e.status == 'failed';
    final fg = failed ? const Color(0xFFC0392B) : const Color(0xFF92600A);
    final bg = failed ? const Color(0xFFFDE8E8) : const Color(0xFFFEF3DC);
    final when = DateFormat('dd MMM, HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(e.createdAt));
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E7D8))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(e.label,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: idaDark)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(20)),
            child: Text(failed ? loc.offChipFailed : loc.offChipWaiting,
                style: TextStyle(
                    color: fg, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(loc.offSavedAt(when),
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        if (failed && e.error.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(e.error,
              style: TextStyle(color: fg, fontSize: 12.5, height: 1.3)),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (!failed)
            ElevatedButton.icon(
              onPressed: () => Offline.flush(),
              icon: const Icon(Icons.send, size: 16, color: Colors.white),
              label: Text(loc.offSendNow,
                  style: const TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
            ),
          if (failed) ...[
            ElevatedButton.icon(
              onPressed: () => Offline.retry(e.id),
              icon: const Icon(Icons.refresh, size: 16, color: Colors.white),
              label: Text(loc.offTryAgain,
                  style: const TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
            ),
            OutlinedButton.icon(
              onPressed: () => _discard(e),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: Text(loc.offDiscard),
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red)),
            ),
          ],
        ]),
      ]),
    );
  }
}
