// lib/screens/admin/admin_common.dart
//
// Shared pieces for the phone's admin screens (Oct 2026, group F):
// Users & permissions, Password manager, App settings and the factory
// tractor diesel log. Colours match the website's redesign.
//  - AdminApi: JSON calls to the backend with the login token (and any
//    extra headers, e.g. the password manager's x-password-token).
//    A failed call throws AdminApiError with the server's message.
//  - small widgets: card, status chip, error box, avatar, snack bars.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../localization/app_localizations.dart';
import '../../services/api_client.dart';
import '../../services/api_service.dart';

const Color aGreen = Color(0xFF3B7A28);
const Color aGreenDark = Color(0xFF2C5E17);
const Color aDark = Color(0xFF1E3313);
const Color aBg = Color(0xFFF4F5F1);
const Color aBorder = Color(0xFFE0E7D8);
const Color aLine = Color(0xFFEEF1EA);
const Color aMuted = Color(0xFF5F6A58);
const Color aText = Color(0xFF1A2812);
const Color aRed = Color(0xFF9E2419);
const Color aAmber = Color(0xFF7A4D00);
const Color aOrange = Color(0xFFB0520C);
const Color aBlue = Color(0xFF2F5F9E);
const Color aSoftGreen = Color(0xFFE3F0DA);
const Color aSoftAmber = Color(0xFFFCEFD2);
const Color aSoftRed = Color(0xFFFBE2DF);
const Color aSoftGrey = Color(0xFFECEEE8);

class AdminApiError implements Exception {
  final String message;
  final int status;
  final Map<String, dynamic> data;
  AdminApiError(this.message, this.status, this.data);
  @override
  String toString() => message;
}

class AdminApi {
  static Future<dynamic> send(String method, String path, {Object? body, Map<String, String>? headers, String? queueLabel, String? queueKey}) async {
    final b = body == null ? null : jsonEncode(body);
    http.Response res;
    try {
      res = await Api.send(method, path, body: b, headers: headers, timeout: const Duration(seconds: 60), queueLabel: queueLabel, queueKey: queueKey);
    } catch (e) {
      throw AdminApiError(Api.errorText(e), 0, <String, dynamic>{});
    }
    final data = Api.decode(res);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      throw AdminApiError(Api.responseError(res), res.statusCode, map);
    }
    return data;
  }

  static Future<dynamic> get(String path, {Map<String, String>? headers}) => send('GET', path, headers: headers);
  static Future<dynamic> post(String path, [Object? body, Map<String, String>? headers]) => send('POST', path, body: body, headers: headers);
  static Future<dynamic> put(String path, [Object? body]) => send('PUT', path, body: body);
  // Offline entry (phone): same as post/put, but with no signal the entry is
  // kept on the phone and sent later. Check the answer with [wasQueued].
  static Future<dynamic> postQueued(String path, Object? body, {required String queueLabel, required String queueKey}) =>
      send('POST', path, body: body, queueLabel: queueLabel, queueKey: queueKey);
  static Future<dynamic> putQueued(String path, Object? body, {required String queueLabel, required String queueKey}) =>
      send('PUT', path, body: body, queueLabel: queueLabel, queueKey: queueKey);
  /// True when the answer of a queued call means "kept on this phone".
  static bool wasQueued(dynamic data) => data is Map && data['queued'] == true;
  static Future<dynamic> patch(String path, [Object? body]) => send('PATCH', path, body: body);
  static Future<dynamic> delete(String path) => send('DELETE', path);
}

// The signed-in person's user id, read from the login token.
Future<int?> myUserId() async {
  final token = await ApiService.getToken();
  if (token == null) return null;
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    return payload is Map ? int.tryParse('${payload['id']}') : null;
  } catch (_) {
    return null;
  }
}

String errText(Object e) => '$e'.replaceFirst('Exception: ', '');

void showOk(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: aGreen, behavior: SnackBarBehavior.floating));
}

void showErr(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: aRed, behavior: SnackBarBehavior.floating));
}

PreferredSizeWidget adminBar(String title, {List<Widget>? actions, PreferredSizeWidget? bottom}) => AppBar(
      title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      backgroundColor: aDark,
      foregroundColor: Colors.white,
      actions: actions,
      bottom: bottom,
    );

class ACard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? border;
  final Color color;
  const ACard({super.key, required this.child, this.padding = EdgeInsets.zero, this.border, this.color = Colors.white});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12), border: Border.all(color: border ?? aBorder)),
        child: child,
      );
}

class AChip extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const AChip(this.text, {super.key, this.bg = aSoftGrey, this.fg = const Color(0xFF4A5643)});
  const AChip.ok(this.text, {super.key})
      : bg = aSoftGreen,
        fg = aGreenDark;
  const AChip.wait(this.text, {super.key})
      : bg = aSoftAmber,
        fg = aAmber;
  const AChip.bad(this.text, {super.key})
      : bg = aSoftRed,
        fg = aRed;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
      );
}

class AErrorBox extends StatelessWidget {
  final String? text;
  const AErrorBox(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    if (text == null || text!.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFFDF1EF), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFF0C4BE))),
      child: Text(text!, style: const TextStyle(color: aRed, fontSize: 13.5)),
    );
  }
}

class ANote extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool warn;
  const ANote(this.text, {super.key, this.icon = Icons.info_outline, this.warn = false});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: warn ? const Color(0xFFFFF7EA) : const Color(0xFFF3F8EE),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: warn ? const Color(0xFFF3D7A6) : const Color(0xFFCFE3C0)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: warn ? aAmber : const Color(0xFF1F4A0E)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: warn ? const Color(0xFF6A4300) : const Color(0xFF1F4A0E)))),
        ]),
      );
}

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

class AAvatar extends StatelessWidget {
  final String name;
  final bool orange;
  final double size;
  const AAvatar(this.name, {super.key, this.orange = false, this.size = 40});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: orange ? const Color(0xFFFDE6D2) : aSoftGreen),
        child: Text(initialsOf(name), style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * 0.36, color: orange ? const Color(0xFF8C3F06) : aGreenDark)),
      );
}

// A row of filter chips with counts (All 9 · Can sign in 8 …).
class AFilterChips<T> extends StatelessWidget {
  final List<(T, String, int?)> options;
  final T value;
  final ValueChanged<T> onChanged;
  const AFilterChips({super.key, required this.options, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: () => onChanged(o.$1),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: o.$1 == value ? aDark : Colors.white,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: o.$1 == value ? aDark : const Color(0xFFD5DCCD)),
                  ),
                  child: Text(o.$3 == null ? o.$2 : '${o.$2}  ${o.$3}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: o.$1 == value ? Colors.white : const Color(0xFF34422D))),
                ),
              ),
            ),
        ]),
      );
}

InputDecoration aInput(String label, {String? hint, Widget? suffix, String? helper}) => InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFD5DCCD))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFD5DCCD))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: aGreen, width: 1.6)),
    );

ButtonStyle aPrimary({double height = 48}) => FilledButton.styleFrom(
      backgroundColor: aGreen,
      foregroundColor: Colors.white,
      minimumSize: Size(0, height),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
    );

ButtonStyle aSecondary({double height = 44, Color fg = const Color(0xFF2B3A24)}) => OutlinedButton.styleFrom(
      foregroundColor: fg,
      minimumSize: Size(0, height),
      side: BorderSide(color: fg == aRed ? const Color(0xFFE8B4AE) : const Color(0xFFD5DCCD)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
    );

Future<bool> aConfirm(BuildContext context, String title, String body, {String yes = 'Yes', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: danger ? aRed : aGreen),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(yes),
        ),
      ],
    ),
  );
  return r == true;
}

// ─── Master lists: Active / Inactive and Delete-if-never-used ────────────
//
// Shared by the management screens (farms, workers, work types, crops,
// varieties, parties, destinations, tractors, products, orchard blocks).
// The lists are loaded with ?all=1; each row has is_active (0/1) and, with
// ?all=1, used_count (how many records use it).

/// True unless the row says it is inactive (is_active 0 / false).
bool isRowActive(dynamic row) {
  if (row is! Map) return true;
  final v = row['is_active'];
  if (v == null) return true;
  return v == 1 || v == true || v == '1' || v == 'true';
}

/// How many records use this row (null when the list did not say).
int? usedCountOf(dynamic row) {
  if (row is! Map) return null;
  final v = row['used_count'];
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}');
}

/// Segmented "Active / Inactive" chips shown above a master list.
class MasterStatusToggle extends StatelessWidget {
  final bool showInactive;
  final int activeCount;
  final int inactiveCount;
  final ValueChanged<bool> onChanged;
  const MasterStatusToggle({super.key, required this.showInactive, required this.activeCount, required this.inactiveCount, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return AFilterChips<bool>(
      options: [(false, loc.miActive, activeCount), (true, loc.miInactive, inactiveCount)],
      value: showInactive,
      onChanged: onChanged,
    );
  }
}

/// "Mark inactive / Make active" and "Delete" buttons for one master row,
/// to sit at the bottom of its edit dialog or screen. [path] is the row's
/// own URL (for example /farms/5): PATCH {is_active} and DELETE go there.
/// [onDone] runs after either succeeded (the caller closes its dialog and
/// reloads the list); a failure shows the server's words under the buttons.
class MasterLifecycle extends StatefulWidget {
  final String path;
  final String module; // permission module (update / delete levels)
  final String itemName;
  final bool isActive;
  final int? usedCount;
  final void Function(String message) onDone;
  const MasterLifecycle({
    super.key,
    required this.path,
    required this.module,
    required this.itemName,
    required this.isActive,
    required this.usedCount,
    required this.onDone,
  });
  @override
  State<MasterLifecycle> createState() => _MasterLifecycleState();
}

class _MasterLifecycleState extends State<MasterLifecycle> {
  bool _canUpdate = false;
  bool _canDelete = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPerms();
  }

  Future<void> _loadPerms() async {
    final u = await ApiService.canUpdate(widget.module);
    final d = await ApiService.canDelete(widget.module);
    if (!mounted) return;
    setState(() {
      _canUpdate = u;
      _canDelete = d;
    });
  }

  Future<void> _toggle() async {
    final loc = AppLocalizations.of(context)!;
    final msg = widget.isActive ? loc.miMarkedInactive : loc.miMadeActive;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await Api.patch(widget.path, body: {'is_active': !widget.isActive});
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        setState(() => _busy = false);
        widget.onDone(msg);
      } else {
        setState(() {
          _busy = false;
          _error = Api.responseError(res);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = Api.errorText(e);
      });
    }
  }

  Future<void> _delete() async {
    final loc = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(loc.miDeleteTitle),
        content: Text(loc.miDeleteBody(widget.itemName)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: aRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await Api.delete(widget.path);
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        setState(() => _busy = false);
        widget.onDone(loc.miDeleted);
      } else {
        setState(() {
          _busy = false;
          _error = Api.responseError(res);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = Api.errorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canUpdate && !_canDelete) return const SizedBox.shrink();
    final loc = AppLocalizations.of(context)!;
    final used = widget.usedCount ?? 0;
    final inUse = used > 0;
    final canDeleteNow = _canDelete && !inUse && !_busy;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Divider(height: 1),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (_canUpdate)
            OutlinedButton.icon(
              style: aSecondary(height: 40),
              onPressed: _busy ? null : _toggle,
              icon: Icon(widget.isActive ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
              label: Text(widget.isActive ? loc.miMarkInactive : loc.miMakeActive),
            ),
          OutlinedButton.icon(
            style: aSecondary(height: 40, fg: aRed),
            onPressed: canDeleteNow ? _delete : null,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(loc.delete),
          ),
        ]),
        if (inUse && _canDelete)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(loc.miUsedTimes(used), style: const TextStyle(fontSize: 12.5, color: aMuted)),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(fontSize: 12.5, color: aRed)),
          ),
      ]),
    );
  }
}
