import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class BillService {
  /// Builds the bill PDF and downloads it (web) / opens share-save sheet (mobile)
  static Future<void> share({
    required Map<String, dynamic> apt,
    required String symbol,
    required String startTime,
    required String endTime,
  }) async {
    final bytes = await _build(apt, symbol, startTime, endTime);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'bill_${apt['booking_number']}.pdf',
    );
  }

  static String _m(String s, num v) => '$s${v.toStringAsFixed(2)}';

  static pw.Widget _row(String l, String r,
      {bool bold = false, double size = 11, PdfColor? color}) {
    final st = pw.TextStyle(
      fontSize: size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text(l, style: st), pw.Text(r, style: st)],
      ),
    );
  }

  static Future<Uint8List> _build(
    Map<String, dynamic> apt,
    String symbol,
    String startTime,
    String endTime,
  ) async {
    final regular = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    final services = List<Map<String, dynamic>>.from(apt['services'] ?? []);
    final subtotal = (apt['services_total'] as num?)?.toDouble() ?? 0;
    final discount = (apt['total_discount'] as num?)?.toDouble() ?? 0;
    final extra = (apt['extra_charge'] as num?)?.toDouble() ?? 0;
    final extraNote = apt['extra_charge_note'] as String?;
    final total = (apt['price'] as num?)?.toDouble() ?? 0;
    final isPaid = apt['payment_status'] == 'paid';

    String paidAt = '';
    final raw = apt['payment_paid_at'] as String?;
    if (raw != null && raw.isNotEmpty) {
      try {
        paidAt = DateFormat('MMM dd, yyyy  hh:mm a')
            .format(DateTime.parse(raw).toLocal());
      } catch (_) {}
    }

    final childName = apt['child_name'] as String?;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) => [
          pw.Text(
            (apt['salon_name'] ?? 'Salon').toString(),
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text('BILL / RECEIPT',
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
          pw.Divider(thickness: 1.2),
          _row('Booking No', '${apt['booking_number']}'),
          _row('Date', '${apt['display_date']}'),
          _row('Time', '$startTime - $endTime'),
          _row('Customer', '${apt['customer_name']}'),
          if (childName != null && childName.isNotEmpty)
            _row('Booked for', childName),
          _row('Barber', '${apt['barber_name']}'),
          pw.SizedBox(height: 14),
          pw.Text('Services',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.Divider(),
          ...services.map((s) {
            final orig = (s['original_price'] as num?)?.toDouble() ?? 0;
            final disc = (s['discount_amount'] as num?)?.toDouble() ?? 0;
            final fin = (s['final_price'] as num?)?.toDouble() ?? 0;
            final variant = s['variant_label'] as String?;
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('${s['service_name']}',
                            style: const pw.TextStyle(fontSize: 11)),
                        if (variant != null && variant.isNotEmpty)
                          pw.Text(variant,
                              style: const pw.TextStyle(
                                  fontSize: 9, color: PdfColors.grey700)),
                        if (disc > 0)
                          pw.Text(
                            'Offer: ${s['offer_title'] ?? ''}  (-${_m(symbol, disc)})',
                            style: const pw.TextStyle(
                                fontSize: 9, color: PdfColors.green800),
                          ),
                      ],
                    ),
                  ),
                  pw.Text(_m(symbol, disc > 0 ? fin : orig),
                      style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
            );
          }),
          pw.Divider(),
          _row('Subtotal', _m(symbol, subtotal)),
          if (discount > 0)
            _row('Discount', '-${_m(symbol, discount)}',
                color: PdfColors.green800),
          if (extra > 0)
            _row(
              extraNote != null && extraNote.isNotEmpty
                  ? 'Extra ($extraNote)'
                  : 'Extra charge',
              '+${_m(symbol, extra)}',
            ),
          pw.Divider(thickness: 1.2),
          _row('TOTAL', _m(symbol, total), bold: true, size: 15),
          pw.SizedBox(height: 10),
          _row('Payment', isPaid ? 'PAID' : 'UNPAID',
              bold: true,
              color: isPaid ? PdfColors.green800 : PdfColors.orange800),
          if (isPaid && paidAt.isNotEmpty) _row('Paid at', paidAt),
          pw.SizedBox(height: 24),
          pw.Center(
            child: pw.Text('Thank you!',
                style: const pw.TextStyle(
                    fontSize: 12, color: PdfColors.grey700)),
          ),
        ],
      ),
    );

    return doc.save();
  }
}