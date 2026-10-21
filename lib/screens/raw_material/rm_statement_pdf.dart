// lib/screens/raw_material/rm_statement_pdf.dart
//
// A supplier statement as a PDF file (for WhatsApp, e-mail, print), built
// from the same data the supplier ledger screen shows. The built-in PDF fonts
// have no rupee sign, so amounts are written as "Rs".

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'rm_common.dart';

String _rs(dynamic v) => inr(v).replaceAll('₹', 'Rs ').replaceAll('−', '-');

Future<File> buildStatementPdf(Map<String, dynamic> data) async {
  final period = data['period'] is Map ? data['period'] as Map : const {};
  final lines = ((data['lines'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final balance = toD(data['balance']);

  String particulars(Map<String, dynamic> l) {
    final r = l['receipt'];
    if (r is Map) {
      final parts = <String>[
        '${r['label'] ?? 'Purchase'}',
        if (r['vehicle'] != null) r['vehicle'].toString(),
        '${mt(r['qty_mt'])} MT${toD(r['cut_mt']) > 0 ? ' (${mt(r['gross_mt'])} - ${mt(r['cut_mt'])} cut)' : ''} x ${_rs(r['rate_per_mt'])}',
        if (toD(r['deduction']) != 0) '(deduction ${_rs(r['deduction'])})',
      ];
      return parts.join('  ');
    }
    if (toD(l['debit']) > 0) return 'Payment';
    return (l['voucher_type'] ?? 'Entry').toString();
  }

  final rows = <List<String>>[
    [dmy(period['from']), 'Opening balance', '', _rs(data['opening_at_from'])],
    for (final l in lines)
      [
        dm(l['date']),
        particulars(l),
        toD(l['debit']) > 0 ? '- ${_rs(l['debit'])}' : '+ ${_rs(l['credit'])}',
        _rs(l['balance']),
      ],
  ];

  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (ctx) => [
      pw.Text('IDA AgriCo', style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
      pw.Text('Statement: ${data['party']}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      pw.Text('${dmy(period['from'])} to ${dmy(period['to'])}', style: const pw.TextStyle(fontSize: 11)),
      pw.SizedBox(height: 12),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Purchases ${_rs(data['period_purchases'])}  (${mt(data['period_qty_mt'])} MT)', style: const pw.TextStyle(fontSize: 11)),
        pw.Text('Paid ${_rs(data['period_paid'])}', style: const pw.TextStyle(fontSize: 11)),
      ]),
      pw.SizedBox(height: 4),
      pw.Text(
        balance < -0.004 ? 'Paid in advance: ${_rs(-balance)}' : 'Amount to pay: ${_rs(balance)}',
        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 12),
      pw.TableHelper.fromTextArray(
        headers: const ['Date', 'Particulars', 'Amount', 'Balance'],
        data: rows,
        headerStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 9.5),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        columnWidths: {0: const pw.FixedColumnWidth(50), 1: const pw.FlexColumnWidth(), 2: const pw.FixedColumnWidth(80), 3: const pw.FixedColumnWidth(80)},
        cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerLeft, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
      ),
      pw.SizedBox(height: 10),
      pw.Text('From TallyPrime, updated ${whenText((data['status'] is Map ? (data['status'] as Map)['last_ok_at'] : null))}.',
          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
    ],
  ));

  final dir = await getTemporaryDirectory();
  final safe = data['party'].toString().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  final file = File('${dir.path}/statement_${safe}_${period['from']}_${period['to']}.pdf');
  await file.writeAsBytes(await doc.save());
  return file;
}
