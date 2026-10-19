import 'package:flutter_test/flutter_test.dart';
import 'package:trip_split_gujarat/receipt_scanner.dart';

void main() {
  test('reads the grand total, not the subtotal or tax', () {
    final scan = ReceiptScanner.parse('''
SHREE THAKER BHOJANALAY
Opp. Town Hall, Ahmedabad
GSTIN 24ABCDE1234F1Z5
Date: 12/10/2026  Time 13:42
Gujarati Thali x2    640.00
Buttermilk x2        60.00
Sub Total            700.00
CGST 2.5%            17.50
SGST 2.5%            17.50
Grand Total        ₹ 735.00
Cash Tendered        800.00
''');
    expect(scan.amount, 735);
    expect(scan.title, 'Shree Thaker Bhojanalay');
    expect(scan.category, 'Food');
  });

  test('total on the line after the label, with thousands separators', () {
    final scan = ReceiptScanner.parse('''
Reliance Fresh
Invoice No 4521
Net Amount Payable
Rs. 1,249.50
''');
    expect(scan.amount, 1249.50);
    expect(scan.title, 'Reliance Fresh');
  });

  test('falls back to the largest money-looking number', () {
    final scan = ReceiptScanner.parse('''
Cafe Coffee Day
Cappuccino 180.00
Brownie 120.00
300.00
''');
    expect(scan.amount, 300);
  });

  test('empty text gives an empty scan', () {
    expect(ReceiptScanner.parse('').isEmpty, isTrue);
  });
}
