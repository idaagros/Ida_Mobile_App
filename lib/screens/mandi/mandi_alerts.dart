// lib/screens/mandi/mandi_alerts.dart
//
// Mandi price alerts: "tell me when this crop reaches ₹X per quintal".
// Each user's own. An alert fires once (push notification + the bell
// list), then pauses until re-armed.
//
//   MandiAlertsScreen — for one crop: set / edit / re-arm / delete
//                       (bell icon on the crop screen)
//   MyAlertsCard      — on the Mandi Prices overview: all my alerts
//
// Web counterpart: src/pages/mandi/PriceAlerts.jsx.

import 'package:flutter/material.dart';
import 'mandi_common.dart';

String _alertMarket(Map a) =>
    (a['market_name'] ?? '').toString().isNotEmpty ? a['market_name'].toString() : 'any tracked market';

class MandiAlertsScreen extends StatefulWidget {
  final int commodityId;
  final String commodityName;
  const MandiAlertsScreen({super.key, required this.commodityId, required this.commodityName});
  @override
  State<MandiAlertsScreen> createState() => _MandiAlertsScreenState();
}

class _MandiAlertsScreenState extends State<MandiAlertsScreen> {
  bool loading = true;
  bool busy = false;
  String? error;
  String? message;
  bool messageOk = true;
  List<Map<String, dynamic>> alerts = [];
  List<Map<String, dynamic>> markets = [];
  final targetCtrl = TextEditingController();
  String marketId = 'all';

  @override
  void initState() {
    super.initState();
    _loadMarkets();
    _load();
  }

  @override
  void dispose() {
    targetCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMarkets() async {
    try {
      final m = await MandiApi.get('/mandi/markets');
      if (!mounted) return;
      setState(() => markets = List<Map<String, dynamic>>.from(m)
          .where((x) => x['is_active'] == 1 || x['is_active'] == true)
          .toList());
    } catch (_) {
      // Market choice is optional — "any tracked market" still works.
    }
  }

  Future<void> _load() async {
    try {
      final data = await MandiApi.get('/mandi/alerts?commodity_id=${widget.commodityId}');
      if (!mounted) return;
      setState(() {
        alerts = List<Map<String, dynamic>>.from(data);
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _run(Future<dynamic> Function() action, String okText) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final r = await action();
      await _load();
      if (!mounted) return;
      setState(() {
        messageOk = true;
        message = (r is Map && r['status'] == 'triggered')
            ? 'Already at ${rupees(r['triggered_price'])} (${r['triggered_market']}) — you\'ve been notified, and the alert is paused.'
            : okText;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          messageOk = false;
          message = e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _create() {
    final target = double.tryParse(targetCtrl.text.trim());
    if (target == null || target <= 0) {
      setState(() {
        messageOk = false;
        message = 'Enter a target price in ₹ per quintal';
      });
      return;
    }
    FocusScope.of(context).unfocus();
    _run(() async {
      final r = await MandiApi.post('/mandi/alerts', {
        'commodity_id': widget.commodityId,
        'target_price': target,
        'market_id': marketId == 'all' ? null : int.tryParse(marketId),
      });
      targetCtrl.clear();
      return r;
    }, 'Alert set — you\'ll be notified when ${widget.commodityName} reaches ${rupees(target)}.');
  }

  Future<void> _edit(Map<String, dynamic> a) async {
    final ctrl = TextEditingController(text: toD(a['target_price'])?.round().toString() ?? '');
    final rearm = a['status'] == 'triggered';
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(rearm ? 'Re-arm alert' : 'Edit alert'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Target price (₹/quintal)', prefixText: '₹'),
          ),
          if (a['current'] != null) ...[
            const SizedBox(height: 8),
            Text('Now ${rupees(a['current']['price'])} at ${a['current']['market']}. A target at or below this notifies you straight away.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: mandiGreen),
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.trim())),
            child: Text(rearm ? 'Re-arm' : 'Save', style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (value == null || value <= 0) return;
    _run(() => MandiApi.patch('/mandi/alerts/${a['id']}', {'target_price': value}), 'Alert updated and watching again.');
  }

  Future<void> _delete(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this alert?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) _run(() => MandiApi.delete('/mandi/alerts/${a['id']}'), 'Alert deleted.');
  }

  @override
  Widget build(BuildContext context) {
    final anyCurrent = alerts.firstWhere((a) => a['market_id'] == null && a['current'] != null, orElse: () => {})['current'];
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F6),
      appBar: AppBar(
        title: Text('${widget.commodityName} · price alerts'),
        backgroundColor: mandiDark,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(14), children: [
          MandiCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Alert me when the price reaches',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: mandiDark)),
              const SizedBox(height: 10),
              TextField(
                controller: targetCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Target price (₹ per quintal)',
                  prefixText: '₹',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: marketId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'At', isDense: true, border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('Any tracked market')),
                  ...markets.map((m) => DropdownMenuItem(
                        value: m['id'].toString(),
                        child: Text(marketName(m), overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) => setState(() => marketId = v ?? 'all'),
              ),
              if (anyCurrent is Map) ...[
                const SizedBox(height: 8),
                Text(
                  'Best price in the last week: ${rupees(anyCurrent['price'])} at ${anyCurrent['market']} (${dayMonth(anyCurrent['date'])}).',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: mandiGreen, padding: const EdgeInsets.symmetric(vertical: 12)),
                  icon: busy
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.notifications_active_outlined, color: Colors.white, size: 18),
                  label: const Text('Set alert', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  onPressed: busy ? null : _create,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(message!,
                    style: TextStyle(fontSize: 12.5, color: messageOk ? mandiGreen : Colors.red.shade700)),
              ],
            ]),
          ),
          if (error != null) ErrorBox(error!),
          if (loading)
            const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
          else if (alerts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('No alerts for ${widget.commodityName} yet.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
            )
          else ...[
            const SectionLabel('My alerts'),
            ...alerts.map(_alertTile),
          ],
        ]),
      ),
    );
  }

  Widget _alertTile(Map<String, dynamic> a) {
    final reached = a['status'] == 'triggered';
    final current = a['current'] as Map<String, dynamic>?;
    final target = toD(a['target_price']) ?? 0;
    final gap = current == null ? null : target - (toD(current['price']) ?? 0);
    return MandiCard(
      color: reached ? const Color(0xFFF3F7EF) : null,
      borderColor: reached ? const Color(0xFFC9D6BF) : null,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('≥ ${rupees(target)}  ·  ${_alertMarket(a)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: mandiDark)),
            const SizedBox(height: 4),
            Text(
              reached
                  ? '✅ Reached ${rupees(a['triggered_price'])} at ${a['triggered_market']} on ${dayMonth(a['triggered_date'])} — paused'
                  : '👀 Watching',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: reached ? FontWeight.w600 : FontWeight.normal,
                  color: reached ? mandiGreen : Colors.grey.shade700),
            ),
            const SizedBox(height: 2),
            Text(
              current == null
                  ? 'No price in the last week'
                  : 'Now ${rupees(current['price'])} at ${current['market']} (${dayMonth(current['date'])})'
                      '${!reached && gap != null && gap > 0 ? ' · ${rupees(gap)} to go' : ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ]),
        ),
        PopupMenuButton<String>(
          onSelected: (v) => v == 'delete' ? _delete(a) : _edit(a),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'edit', child: Text(reached ? 'Re-arm…' : 'Edit target')),
            const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
          ],
        ),
      ]),
    );
  }
}

/// All of the user's alerts, as a compact card on the overview. Tapping
/// one opens that crop. Shows nothing when there are no alerts.
class MyAlertsCard extends StatelessWidget {
  final List<Map<String, dynamic>> alerts;
  final void Function(Map<String, dynamic> alert) onTap;
  const MyAlertsCard({super.key, required this.alerts, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();
    final reached = alerts.where((a) => a['status'] == 'triggered').length;
    return MandiCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.notifications_active_outlined, size: 16, color: mandiGreen),
          const SizedBox(width: 6),
          const Expanded(
              child: Text('My price alerts',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: mandiDark))),
          Text('${alerts.length - reached} watching${reached > 0 ? ' · $reached reached' : ''}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: alerts.map((a) {
          final hit = a['status'] == 'triggered';
          final current = a['current'] as Map<String, dynamic>?;
          final market = (a['market_name'] ?? '').toString();
          return InkWell(
            onTap: () => onTap(a),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: hit ? mandiTint : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: hit ? const Color(0xFFC9D6BF) : Colors.grey.shade300),
              ),
              child: Text(
                '${a['commodity_name']} ≥ ${rupees(a['target_price'])}'
                '${market.isNotEmpty ? ' · $market' : ''}'
                '${hit ? ' ✅' : (current != null ? ' (now ${rupees(current['price'])})' : '')}',
                style: TextStyle(fontSize: 12, color: hit ? mandiDark : Colors.grey.shade800),
              ),
            ),
          );
        }).toList()),
      ]),
    );
  }
}
