// lib/widgets/offline_status_bar.dart
//
// Slim strip shown at the top of screens that work without signal.
// Shows nothing when everything is clear. Otherwise one of:
//   - "Offline - showing saved data"        (screen is showing saved answers)
//   - "N waiting to send" + [Send now]      (entries kept on the phone)
//   - "N not sent - tap to review"          (entries the server refused)
// Tapping the waiting / not-sent strip opens the list ('/offline').
import 'package:flutter/material.dart';
import '../localization/app_localizations.dart';
import '../services/offline_queue.dart';

class OfflineStatusBar extends StatelessWidget {
  const OfflineStatusBar({super.key});

  static const _green = Color(0xFF3B7A28);
  static const _greenBg = Color(0xFFE8F5E2);
  static const _amber = Color(0xFF92600A);
  static const _amberBg = Color(0xFFFEF3DC);
  static const _red = Color(0xFFC0392B);
  static const _redBg = Color(0xFFFDE8E8);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        Offline.pendingCount,
        Offline.failedCount,
        Offline.showingSaved,
      ]),
      builder: (context, _) {
        final loc = AppLocalizations.of(context)!;
        final pending = Offline.pendingCount.value;
        final failed = Offline.failedCount.value;
        final saved = Offline.showingSaved.value;
        if (pending == 0 && failed == 0 && !saved) {
          return const SizedBox.shrink();
        }
        final strips = <Widget>[];
        if (failed > 0) {
          strips.add(_strip(
            context,
            icon: Icons.error_outline,
            fg: _red,
            bg: _redBg,
            text: loc.offFailed(failed),
            onTap: () => Navigator.pushNamed(context, '/offline'),
          ));
        }
        if (pending > 0) {
          strips.add(_strip(
            context,
            icon: Icons.cloud_upload_outlined,
            fg: _amber,
            bg: _amberBg,
            text: loc.offWaiting(pending),
            action: loc.offSendNow,
            onAction: () => Offline.flush(),
            onTap: () => Navigator.pushNamed(context, '/offline'),
          ));
        }
        if (saved) {
          strips.add(_strip(
            context,
            icon: Icons.cloud_off_outlined,
            fg: _green,
            bg: _greenBg,
            text: loc.offStatusSaved,
          ));
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < strips.length; i++) ...[
                if (i > 0) const SizedBox(height: 6),
                strips[i],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _strip(
    BuildContext context, {
    required IconData icon,
    required Color fg,
    required Color bg,
    required String text,
    String? action,
    VoidCallback? onAction,
    VoidCallback? onTap,
  }) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Icon(icon, color: fg, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: fg, fontWeight: FontWeight.w600, fontSize: 12.5),
              ),
            ),
            if (action != null && onAction != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: fg,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: BorderSide(color: fg.withOpacity(0.5)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(action,
                    maxLines: 1,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
