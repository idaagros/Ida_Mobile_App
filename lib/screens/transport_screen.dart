// lib/screens/transport_screen.dart
//
// Transport Directory — categorised list of transporters with call and
// WhatsApp support. Ported from the CCA project to use the
// Ida AgriCo Node.js/MySQL backend.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_client.dart';
import '../services/api_service.dart';
import '../services/responsive.dart';

class TransportScreen extends StatefulWidget {
  const TransportScreen({super.key});
  @override
  State<TransportScreen> createState() => _TransportScreenState();
}

class _TransportScreenState extends State<TransportScreen> {
  static const primaryColor = Color(0xFF1E4012);

  bool _isSearching = false;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  List _categories = [];
  List _searchResults = [];
  bool _loading = true;
  // Transport directory levels (admin has all): add category / entry = Add,
  // edit entry = Update, delete category / entry = Delete.
  bool _canAdd = false;
  bool _canUpdate = false;
  bool _canDelete = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    _canAdd = await ApiService.canAdd('transport');
    _canUpdate = await ApiService.canUpdate('transport');
    _canDelete = await ApiService.canDelete('transport');
    await _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _loading = true);
    try {
      final res = await Api.get('/transport/categories');
      if (res.statusCode == 200) {
        setState(() => _categories = jsonDecode(res.body));
      }
    } catch (e) {
      debugPrint('Load error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _searchTransporters(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    try {
      final res = await Api.get(
          '/transport/entries?search=${Uri.encodeComponent(query)}');
      if (res.statusCode == 200)
        setState(() => _searchResults = jsonDecode(res.body));
    } catch (e) {
      debugPrint('Search error: $e');
    }
  }

  Future<void> _makeCall(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openWhatsApp(String phone) async {
    String clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (!clean.startsWith('+')) clean = '+91$clean';
    final uri = Uri.parse('https://wa.me/$clean');
    if (await canLaunchUrl(uri))
      await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  IconData _categoryIcon(String? key) {
    switch (key) {
      case 'local':
        return Icons.location_city;
      case 'upcountry':
        return Icons.terrain;
      case 'courier':
        return Icons.bolt;
      case 'interstate':
        return Icons.map;
      default:
        return Icons.local_shipping;
    }
  }

  List<Color> _categoryColors(String? key) {
    switch (key) {
      case 'local':
        return [const Color(0xFF0D47A1), const Color(0xFF1976D2)];
      case 'upcountry':
        return [const Color(0xFF1B5E20), const Color(0xFF388E3C)];
      case 'courier':
        return [const Color(0xFFE65100), const Color(0xFFF57C00)];
      case 'interstate':
        return [const Color(0xFF4A148C), const Color(0xFF7B1FA2)];
      default:
        return [primaryColor, const Color(0xFF3B7A28)];
    }
  }

  void _showAddCategoryDialog() {
    final nameCtrl = TextEditingController();
    String? selectedKey;

    final choices = {
      'local': 'Local',
      'upcountry': 'Upcountry',
      'courier': 'Courier',
      'interstate': 'Interstate',
    };

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Add Category',
              style: TextStyle(fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Category Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            const Align(
                alignment: Alignment.centerLeft,
                child: Text('Type:',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: choices.entries.map((e) {
                final selected = selectedKey == e.key;
                final colors = _categoryColors(e.key);
                return GestureDetector(
                  onTap: () => setS(() => selectedKey = e.key),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? colors[0] : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(e.value,
                        style: TextStyle(
                            color: selected ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600)),
                  ),
                );
              }).toList(),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCEL')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final res = await Api.post(
                  '/transport/categories',
                  body: jsonEncode({
                    'name': nameCtrl.text.trim(),
                    'icon': selectedKey ?? 'local_shipping',
                    'color': selectedKey ?? 'local'
                  }),
                );
                if (!mounted) return;
                Navigator.pop(ctx);
                if (res.statusCode == 200) {
                  _loadCategories();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(Api.responseError(res)),
                      backgroundColor: Colors.red));
                }
              },
              child:
                  const Text('CREATE', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _openCategory(Map cat) {
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _TransportCategoryScreen(
            category: cat,
            colors: _categoryColors(cat['color']?.toString()),
            icon: _categoryIcon(cat['icon']?.toString()),
            canAdd: _canAdd,
            canUpdate: _canUpdate,
            canDelete: _canDelete,
          ),
        )).then((_) => _loadCategories());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: _isSearching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                    hintText: 'Search all transporters...',
                    hintStyle: TextStyle(color: Colors.white70),
                    border: InputBorder.none),
                onChanged: (v) {
                  setState(() => _searchQuery = v);
                  _searchTransporters(v);
                },
              )
            : const Text('Transport Directory',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                _searchQuery = '';
                _searchCtrl.clear();
                _searchResults = [];
              });
            },
          ),
        ],
      ),
      body: Responsive.constrainedContent(
          context,
          _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF3B7A28)))
              : _isSearching && _searchQuery.isNotEmpty
                  ? _buildSearchResults()
                  : _buildCategoryGrid(),
          maxWidth: 600),
      floatingActionButton: _canAdd
          ? FloatingActionButton(
              backgroundColor: primaryColor,
              onPressed: _showAddCategoryDialog,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildCategoryGrid() {
    if (_categories.isEmpty) {
      return const Center(
          child: Text('No categories yet. Tap + to create one.',
              style: TextStyle(color: Colors.grey)));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 1.3),
      itemCount: _categories.length,
      itemBuilder: (_, i) {
        final cat = _categories[i];
        final colors = _categoryColors(cat['color']?.toString());
        final icon = _categoryIcon(cat['icon']?.toString());
        final count = cat['entry_count'] ?? 0;
        return GestureDetector(
          onLongPress: _canDelete ? () => _confirmDeleteCategory(cat) : null,
          onTap: () => _openCategory(cat),
          child: Container(
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors),
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                      color: colors[0].withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4))
                ]),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: Colors.white, size: 32),
              const SizedBox(height: 8),
              Text(cat['name'] ?? '',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              Text('$count ${count == 1 ? 'transporter' : 'transporters'}',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.8), fontSize: 11)),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return const Center(child: Text('No transporters found'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _searchResults.length,
      itemBuilder: (_, i) {
        final e = _searchResults[i];
        final colors = _categoryColors(e['color']?.toString());
        return Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: CircleAvatar(
                backgroundColor: colors[0].withOpacity(0.1),
                child: Icon(Icons.local_shipping, color: colors[0])),
            title: Text(e['name'] ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                '${e['location'] ?? ''}${e['phone'] != null ? ' · ${e['phone']}' : ''}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                  icon: const Icon(Icons.call, color: Colors.green),
                  onPressed: () => _makeCall(e['phone'] ?? '')),
              IconButton(
                  icon: const Icon(Icons.message, color: Colors.blue),
                  onPressed: () => _openWhatsApp(e['phone'] ?? '')),
            ]),
          ),
        );
      },
    );
  }

  void _confirmDeleteCategory(Map cat) async {
    if ((cat['entry_count'] ?? 0) > 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Delete all entries in this category first.'),
          backgroundColor: Colors.red));
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete "${cat['name']}"?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('Delete', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirm != true) return;
    await Api.delete('/transport/categories/${cat['id']}');
    _loadCategories();
  }
}

// ── Per-category entry list ────────────────────────────────────────────────
class _TransportCategoryScreen extends StatefulWidget {
  final Map category;
  final List<Color> colors;
  final IconData icon;
  final bool canAdd;
  final bool canUpdate;
  final bool canDelete;
  const _TransportCategoryScreen(
      {required this.category,
      required this.colors,
      required this.icon,
      required this.canAdd,
      required this.canUpdate,
      required this.canDelete});
  @override
  State<_TransportCategoryScreen> createState() =>
      _TransportCategoryScreenState();
}

class _TransportCategoryScreenState extends State<_TransportCategoryScreen> {
  List _entries = [];
  String _search = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Api.get(
          '/transport/entries?category_id=${widget.category['id']}');
      if (res.statusCode == 200)
        setState(() => _entries = jsonDecode(res.body));
    } catch (e) {
      debugPrint('Load entries error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _makeCall(String p) async {
    final uri = Uri(scheme: 'tel', path: p);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openWhatsApp(String p) async {
    String c = p.replaceAll(RegExp(r'[^\d]'), '');
    if (c.length == 10) c = '91$c';
    final uri = Uri.parse('https://wa.me/$c');
    if (await canLaunchUrl(uri))
      await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showEntry(Map entry, {bool isEdit = false}) {
    final nameCtrl =
        TextEditingController(text: entry['name']?.toString() ?? '');
    final gstCtrl = TextEditingController(text: entry['gst']?.toString() ?? '');
    final contactCtrl =
        TextEditingController(text: entry['contact_person']?.toString() ?? '');
    final phoneCtrl =
        TextEditingController(text: entry['phone']?.toString() ?? '');
    final addPhoneCtrl = TextEditingController(
        text: entry['additional_phone']?.toString() ?? '');
    final locCtrl =
        TextEditingController(text: entry['location']?.toString() ?? '');
    final remarkCtrl =
        TextEditingController(text: entry['remarks']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(isEdit ? 'Edit Transporter' : 'Add Transporter',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _field(nameCtrl, 'Transport Name *'),
            _field(locCtrl, 'For Location'),
            _field(gstCtrl, 'GST Number'),
            _field(contactCtrl, 'Contact Person'),
            _field(phoneCtrl, 'Phone *', isPhone: true),
            _field(addPhoneCtrl, 'Additional Phone', isPhone: true),
            _field(remarkCtrl, 'Remarks', maxLines: 3),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: widget.colors[0]),
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty || phoneCtrl.text.trim().isEmpty)
                return;
              final body = jsonEncode({
                'category_id': widget.category['id'],
                'name': nameCtrl.text.trim(),
                'gst': gstCtrl.text.trim(),
                'contact_person': contactCtrl.text.trim(),
                'phone': phoneCtrl.text.trim(),
                'additional_phone': addPhoneCtrl.text.trim(),
                'location': locCtrl.text.trim(),
                'remarks': remarkCtrl.text.trim(),
              });
              if (isEdit) {
                await Api.put('/transport/entries/${entry['id']}', body: body);
              } else {
                await Api.post('/transport/entries', body: body);
              }
              if (!mounted) return;
              Navigator.pop(context);
              _load();
            },
            child: Text(isEdit ? 'UPDATE' : 'SAVE',
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showDetails(Map entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, sc) => SingleChildScrollView(
            controller: sc,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                        child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(10)))),
                    const SizedBox(height: 16),
                    Row(children: [
                      CircleAvatar(
                          radius: 28,
                          backgroundColor: widget.colors[0].withOpacity(0.1),
                          child: Icon(widget.icon,
                              color: widget.colors[0], size: 28)),
                      const SizedBox(width: 14),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(entry['name'] ?? '',
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.bold)),
                            if (entry['location'] != null &&
                                entry['location'].toString().isNotEmpty)
                              Text(entry['location'].toString(),
                                  style:
                                      TextStyle(color: Colors.grey.shade600)),
                          ])),
                    ]),
                    const SizedBox(height: 16),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _actionBtn(Icons.call, 'Call', Colors.green,
                              () => _makeCall(entry['phone'] ?? '')),
                          if (entry['additional_phone'] != null &&
                              entry['additional_phone'].toString().isNotEmpty)
                            _actionBtn(
                                Icons.phone,
                                'Call 2',
                                Colors.teal,
                                () =>
                                    _makeCall(entry['additional_phone'] ?? '')),
                          _actionBtn(Icons.message, 'WhatsApp', Colors.blue,
                              () => _openWhatsApp(entry['phone'] ?? '')),
                          if (widget.canUpdate)
                            _actionBtn(Icons.edit, 'Edit', Colors.orange, () {
                              Navigator.pop(context);
                              _showEntry(entry, isEdit: true);
                            }),
                        ]),
                    const Divider(height: 32),
                    _detail(Icons.assignment_ind, 'Contact Person',
                        entry['contact_person']),
                    _detail(Icons.phone, 'Phone', entry['phone']),
                    _detail(Icons.phone_outlined, 'Additional Phone',
                        entry['additional_phone']),
                    _detail(Icons.receipt_long, 'GST', entry['gst']),
                    _detail(Icons.location_on, 'Location', entry['location']),
                    _detail(Icons.note, 'Remarks', entry['remarks']),
                    if (widget.canDelete) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red)),
                            onPressed: () {
                              Navigator.pop(context);
                              _deleteEntry(entry);
                            },
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Delete'),
                          )),
                    ],
                  ]),
            )),
      ),
    );
  }

  Future<void> _deleteEntry(Map entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text('Delete "${entry['name']}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('Delete', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirm != true) return;
    await Api.delete('/transport/entries/${entry['id']}');
    _load();
  }

  Widget _field(TextEditingController ctrl, String label,
          {bool isPhone = false, int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
            controller: ctrl,
            keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
            maxLines: maxLines,
            decoration: InputDecoration(
                labelText: label, border: const OutlineInputBorder())),
      );

  Widget _detail(IconData icon, String label, dynamic value) {
    if (value == null || value.toString().isEmpty)
      return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(value.toString(),
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ])),
        IconButton(
            icon: const Icon(Icons.copy, size: 16, color: Colors.blue),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value.toString()));
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('$label copied')));
            }),
      ]),
    );
  }

  Widget _actionBtn(
          IconData icon, String label, Color color, VoidCallback onTap) =>
      InkWell(
          onTap: onTap,
          child: Column(children: [
            CircleAvatar(
                backgroundColor: color.withOpacity(0.1),
                child: Icon(icon, color: color)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 10, color: color, fontWeight: FontWeight.bold)),
          ]));

  @override
  Widget build(BuildContext context) {
    final themeColor = widget.colors[0];
    final filtered = _entries.where((e) {
      final s = _search.toLowerCase();
      return (e['name'] ?? '').toString().toLowerCase().contains(s) ||
          (e['gst'] ?? '').toString().toLowerCase().contains(s) ||
          (e['location'] ?? '').toString().toLowerCase().contains(s) ||
          (e['phone'] ?? '').toString().contains(s);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.category['name'] ?? '',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const Text('Transport Directory',
              style: TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: 'Search by Name, GST or Location...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: Responsive.constrainedContent(
              context,
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Text(
                              _search.isNotEmpty
                                  ? 'No results for "$_search"'
                                  : 'No transporters yet. Tap + to add.',
                              style: const TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final e = filtered[i];
                            return Card(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                    backgroundColor:
                                        themeColor.withOpacity(0.1),
                                    child: Icon(widget.icon,
                                        color: themeColor, size: 20)),
                                title: Text(e['name'] ?? '',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (e['gst'] != null &&
                                          e['gst'].toString().isNotEmpty)
                                        Text('GST: ${e['gst']}',
                                            style:
                                                const TextStyle(fontSize: 12)),
                                      if (e['phone'] != null)
                                        Text('Phone: ${e['phone']}',
                                            style:
                                                const TextStyle(fontSize: 12)),
                                    ]),
                                isThreeLine: true,
                                trailing: const Icon(Icons.arrow_forward_ios,
                                    size: 14),
                                onTap: () => _showDetails(e),
                              ),
                            );
                          },
                        )),
        ),
      ]),
      floatingActionButton: widget.canAdd
          ? FloatingActionButton(
              backgroundColor: themeColor,
              onPressed: () => _showEntry({}, isEdit: false),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }
}
