// lib/screens/agronomy/product_editor_screen.dart
//
// One product: name, kind, the unit doses are written in, its brands
// and which brand is preferred (filled in when a spray is recorded).
// Products made from old typed names are marked "Needs checking" until
// someone taps "Looks right". Brand changes on an existing product
// save straight away; the other fields save with Save.
// The list reloads when this screen closes.

import 'package:flutter/material.dart';
import 'agronomy_common.dart';

class ProductEditorScreen extends StatefulWidget {
  final Map? product; // null = new
  final bool canEdit;
  const ProductEditorScreen({super.key, this.product, required this.canEdit});
  @override
  State<ProductEditorScreen> createState() => _ProductEditorScreenState();
}

class _ProductEditorScreenState extends State<ProductEditorScreen> {
  Map? p;
  final nameCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  final brandCtrl = TextEditingController();
  String? kind;
  String unit = 'ml';
  List<Map> newBrands = []; // new product: {name, preferred}
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    p = widget.product;
    _fill();
  }

  void _fill() {
    nameCtrl.text = p?['name'] ?? '';
    notesCtrl.text = p?['notes'] ?? '';
    kind = p?['product_type'];
    unit = p?['unit'] ?? 'ml';
  }

  bool get isNew => p == null;
  bool get _liquidUnit => unit == 'ml' || unit == 'L';

  Future<void> _run(Future<dynamic> Function() fn) async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final r = await fn();
      if (r is Map && r['id'] != null) p = r;
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => saving = false);
  }

  Future<void> _save({bool checked = false}) async {
    if (nameCtrl.text.trim().isEmpty) {
      setState(() => error = 'Write the product name.');
      return;
    }
    if (kind == null) {
      setState(() => error = 'Choose what kind of product this is.');
      return;
    }
    final oldUnit = p?['unit'];
    final oldLiquid = oldUnit == 'ml' || oldUnit == 'L';
    if (!isNew && oldUnit != unit && oldLiquid != _liquidUnit && (toI(p!['used_in_steps']) ?? 0) > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text('Changing $oldUnit to $unit only changes the label — the dose numbers in ${p!['used_in_steps']} step(s) stay the same. Continue?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
          ],
        ),
      );
      if (ok != true) return;
    }
    final body = {
      'name': nameCtrl.text.trim(),
      'product_type': kind,
      'unit': unit,
      'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
      if (checked) 'needs_check': false,
    };
    if (isNew) {
      final pref = newBrands.where((b) => b['preferred'] == true);
      await _run(() => AgriApi.post('/agri/products', {
            ...body,
            'brands': newBrands.map((b) => b['name']).toList(),
            'preferred_brand': pref.isEmpty ? null : pref.first['name'],
          }));
    } else {
      await _run(() => AgriApi.patch('/agri/products/${p!['id']}', body));
    }
    if (error == null && mounted) {
      agSnack(context, 'Saved');
      setState(_fill);
    }
  }

  Future<void> _addBrand() async {
    final name = brandCtrl.text.trim();
    if (name.isEmpty) return;
    if (isNew) {
      if (newBrands.any((b) => b['name'].toString().toLowerCase() == name.toLowerCase())) return;
      setState(() {
        newBrands.add({'name': name, 'preferred': newBrands.isEmpty});
        brandCtrl.clear();
      });
      return;
    }
    await _run(() => AgriApi.post('/agri/products/${p!['id']}/brands', {'brand_name': name}));
    if (error == null) brandCtrl.clear();
  }

  Future<void> _prefer(Map b) async {
    if (isNew) {
      setState(() {
        for (final x in newBrands) {
          x['preferred'] = x['name'] == b['brand_name'];
        }
      });
      return;
    }
    await _run(() => AgriApi.patch('/agri/products/${p!['id']}', {'preferred_brand_id': b['id']}));
  }

  Future<void> _removeBrand(Map b) async {
    if (isNew) {
      setState(() {
        newBrands.removeWhere((x) => x['name'] == b['brand_name']);
        if (newBrands.isNotEmpty && !newBrands.any((x) => x['preferred'] == true)) newBrands.first['preferred'] = true;
      });
      return;
    }
    await _run(() => AgriApi.delete('/agri/products/${p!['id']}/brands/${b['id']}'));
  }

  Future<void> _toggleActive() async {
    final on = p!['is_active'] == true || p!['is_active'] == 1;
    await _run(() => AgriApi.patch('/agri/products/${p!['id']}', {'is_active': !on}));
  }

  Future<void> _deleteProduct() async {
    setState(() => saving = true);
    try {
      await AgriApi.delete('/agri/products/${p!['id']}');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        saving = false;
        error = e.toString();
      });
    }
  }

  List<Map> get brands {
    if (isNew) return [for (final b in newBrands) {'id': null, 'brand_name': b['name'], 'preferred': b['preferred']}];
    return [
      for (final b in (p!['brands'] as List? ?? []))
        {'id': b['id'], 'brand_name': b['brand_name'], 'preferred': toI(b['id']) == toI(p!['preferred_brand_id'])}
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ed = widget.canEdit;
    final needsCheck = !isNew && (p!['needs_check'] == true || p!['needs_check'] == 1);
    final active = isNew || p!['is_active'] == true || p!['is_active'] == 1;
    final used = isNew ? 0 : (toI(p!['used_in_steps']) ?? 0);
    return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: agDark,
          foregroundColor: Colors.white,
          title: Text(isNew ? 'New product' : p!['name'], style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (needsCheck)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFF7EA), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF3D7A6))),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFB8660B)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Made from an old spray step. Check the kind, unit and preferred brand.', style: TextStyle(fontSize: 13)),
                ),
                if (ed)
                  TextButton(
                    onPressed: saving || kind == null ? null : () => _save(checked: true),
                    child: const Text('Looks right', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
          if (error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
              child: Text(error!, style: TextStyle(color: Colors.red.shade900)),
            ),
          TextField(
            controller: nameCtrl,
            enabled: ed,
            decoration: agInput('Product name', helper: 'The chemical or fertiliser, e.g. “Imidacloprid 17.8% SL” — brands go below.'),
          ),
          const SizedBox(height: 16),
          agLabel('Kind'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in agKindKeys)
              ChoiceChip(
                label: Text(agKinds[k]!.label),
                selected: kind == k,
                selectedColor: agDark,
                labelStyle: TextStyle(color: kind == k ? Colors.white : const Color(0xFF3A4833), fontWeight: FontWeight.w600),
                onSelected: ed ? (_) => setState(() => kind = k) : null,
              ),
          ]),
          const SizedBox(height: 16),
          agLabel('Doses are written in'),
          AgSeg<String>(values: agUnits, labels: agUnits, value: unit, onChanged: ed ? (u) => setState(() => unit = u) : null),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Switching ml ↔ L or g ↔ kg converts the doses already in plans.', style: TextStyle(fontSize: 12, color: agMuted)),
          ),
          const SizedBox(height: 18),
          agLabel('Brands · the preferred one is filled in when recording'),
          Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: agBorder)),
            child: Column(children: [
              if (brands.isEmpty) const ListTile(title: Text('No brands yet.', style: TextStyle(color: agMuted))),
              for (final b in brands)
                ListTile(
                  tileColor: b['preferred'] == true ? const Color(0xFFF3F8EE) : null,
                  leading: Icon(b['preferred'] == true ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: b['preferred'] == true ? agGreen : Colors.grey),
                  title: Row(children: [
                    Flexible(child: Text(b['brand_name'], style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                    if (b['preferred'] == true) ...[
                      const SizedBox(width: 8),
                      const SmallChip('Preferred', bg: Color(0xFFE3F0DA), fg: Color(0xFF2C5E17)),
                    ],
                  ]),
                  trailing: ed ? IconButton(icon: const Icon(Icons.close, size: 18), onPressed: saving ? null : () => _removeBrand(b)) : null,
                  onTap: ed && !saving ? () => _prefer(b) : null,
                ),
            ]),
          ),
          if (ed) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: brandCtrl, decoration: agInput('Add a brand'), onSubmitted: (_) => _addBrand())),
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: saving ? null : _addBrand, icon: const Icon(Icons.add), label: const Text('Add')),
            ]),
          ],
          if (used > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Changing the preferred brand changes it in all $used plan step${used == 1 ? '' : 's'} using this product.',
                  style: const TextStyle(fontSize: 12, color: agMuted)),
            ),
          const SizedBox(height: 16),
          TextField(controller: notesCtrl, enabled: ed, decoration: agInput('Notes (optional)', hint: 'e.g. keep away from rain for 6 hours')),
          if (!isNew && ed) ...[
            const SizedBox(height: 24),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(used == 0 && !active ? 'Delete this product' : (active ? 'Turn off' : 'Turned off'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(used == 0 && !active
                  ? 'Only possible because it isn’t used anywhere.'
                  : active
                      ? 'Stays in plans and records; can’t be added to new steps.'
                      : 'Can’t be added to steps.'),
              trailing: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: active || used == 0 ? Colors.red.shade700 : agDark),
                onPressed: saving ? null : (used == 0 && !active ? _deleteProduct : _toggleActive),
                child: Text(used == 0 && !active ? 'Delete' : (active ? 'Turn off' : 'Turn on')),
              ),
            ),
          ],
        ]),
        bottomNavigationBar: !ed
            ? null
            : SafeArea(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: agBorder))),
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: agGreen, foregroundColor: Colors.white),
                      onPressed: saving ? null : () => _save(),
                      icon: Icon(isNew ? Icons.add : Icons.check),
                      label: Text(saving ? 'Saving…' : (isNew ? 'Add product' : 'Save changes')),
                    ),
                  ),
                ),
              ),
    );
  }
}
