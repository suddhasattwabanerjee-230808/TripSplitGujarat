import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:qr/qr.dart';

/// [link] (a upi://pay link with the payee and the amount) as a QR code PNG:
/// black on white with the quiet zone scanners expect. Shared into a UPI app
/// it reads like any scanned QR, so the payment opens with the amount filled
/// in, which UPI apps allow where a payment link from another app to a
/// personal UPI ID is often declined.
Future<Uint8List> upiQrPng(String link) async {
  final qr = QrImage(QrCode(payload: QrPayload.fromString(link), errorCorrectLevel: QrErrorCorrectLevel.medium));
  const cell = 12.0, quiet = 4;
  final side = (qr.moduleCount + 2 * quiet) * cell;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Rect.fromLTWH(0, 0, side, side), Paint()..color = const Color(0xFFFFFFFF));
  final dark = Paint()..color = const Color(0xFF000000);
  for (var y = 0; y < qr.moduleCount; y++) {
    for (var x = 0; x < qr.moduleCount; x++) {
      if (qr.isDark(y, x)) {
        canvas.drawRect(Rect.fromLTWH((x + quiet) * cell, (y + quiet) * cell, cell, cell), dark);
      }
    }
  }
  final image = await recorder.endRecording().toImage(side.toInt(), side.toInt());
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return png!.buffer.asUint8List();
}
