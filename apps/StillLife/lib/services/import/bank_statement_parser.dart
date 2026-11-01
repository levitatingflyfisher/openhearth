import 'package:intl/intl.dart';
import 'package:csv/csv.dart';

import '../../features/import/domain/parsed_import_item.dart';

/// Column index mapping for a bank statement CSV.
///
/// Defined here (service layer) so [BankStatementParser] is self-contained.
/// The UI imports this from the service — never from the domain layer.
class BankColumnMap {
  final int? dateCol;
  final int? descriptionCol;
  final int? amountCol;

  const BankColumnMap({this.dateCol, this.descriptionCol, this.amountCol});
}

/// Parses bank statement CSV exports into [ParsedImportItem] lists.
///
/// - One signed Amount column: the sign that most rows carry is the
///   purchase sign. A debit-card export marks purchases negative; a credit-card
///   export marks them positive. Rows with the other sign (refunds, payments,
///   credits) are skipped. A tie counts as positive purchases.
/// - Accounting notation `(123.45)` is negative.
/// - Capped at 500 data rows; [parse] result carries a [truncated] flag.
class BankStatementParser {
  static const _rowCap = 500;

  /// Heuristically detects date/description/amount column indices from
  /// the CSV header row.
  BankColumnMap detectColumns(String csvContent) {
    final rows = const CsvToListConverter(eol: '\n').convert(csvContent);
    if (rows.isEmpty) return const BankColumnMap();

    final headers = rows.first
        .map((h) => h.toString().toLowerCase().trim())
        .toList();

    int? find(List<String> keywords) {
      for (int i = 0; i < headers.length; i++) {
        if (keywords.any((k) => headers[i].contains(k))) return i;
      }
      return null;
    }

    return BankColumnMap(
      dateCol: find(['date', 'posted', 'trans']),
      descriptionCol: find([
        'description',
        'merchant',
        'memo',
        'payee',
        'details',
      ]),
      amountCol: find(['amount', 'debit', 'charge', 'withdrawal']),
    );
  }

  /// Parses [csvContent] using the given column mapping.
  ///
  /// Returns a named record `({List<ParsedImportItem> items, bool truncated})`.
  ({List<ParsedImportItem> items, bool truncated}) parse(
    String csvContent,
    BankColumnMap map,
  ) {
    final rows = const CsvToListConverter(eol: '\n').convert(csvContent);
    if (rows.length <= 1) return (items: [], truncated: false);

    final dataRows = rows.skip(1).toList();
    final truncated = dataRows.length > _rowCap;
    final capped = truncated ? dataRows.take(_rowCap) : dataRows;

    // Decide the purchase sign from the whole file, because one row cannot
    // say whether its minus sign is a purchase or a refund.
    var negatives = 0;
    var positives = 0;
    if (map.amountCol != null) {
      for (final row in capped) {
        if (row.length <= map.amountCol!) continue;
        final v = _parseAmount(row[map.amountCol!].toString().trim());
        if (v == null || v == 0) continue;
        v < 0 ? negatives++ : positives++;
      }
    }
    final purchasesAreNegative = negatives > positives;

    final items = <ParsedImportItem>[];
    for (final row in capped) {
      // Amount column is required.
      if (map.amountCol == null || row.length <= map.amountCol!) continue;

      final amountRaw = row[map.amountCol!].toString().trim();
      final signed = _parseAmount(amountRaw);
      if (signed == null || signed == 0) continue;
      if ((signed < 0) != purchasesAreNegative) continue;
      final amount = signed.abs();

      final name =
          map.descriptionCol != null && row.length > map.descriptionCol!
          ? row[map.descriptionCol!].toString().trim()
          : '';
      if (name.isEmpty) continue;

      final purchaseDate = map.dateCol != null && row.length > map.dateCol!
          ? _parseDate(row[map.dateCol!].toString())
          : null;

      items.add(
        ParsedImportItem(
          name: name,
          price: amount,
          purchaseDate: purchaseDate,
          source: ImportSource.bankCsv,
        ),
      );
    }

    return (items: items, truncated: truncated);
  }

  /// Returns the signed amount, or null for an unparseable string.
  /// Accounting notation `(123.45)` is negative.
  double? _parseAmount(String raw) {
    if (raw.isEmpty) return null;
    final accounting = raw.startsWith('(') && raw.endsWith(')');
    final cleaned = raw.replaceAll(RegExp(r'[^\d.\-]'), '');
    try {
      final value = double.parse(cleaned);
      return accounting ? -value.abs() : value;
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseDate(String raw) => parseImportDate(raw);
}

/// Parses a date from a statement/CSV cell. `DateTime.parse` only accepts
/// ISO-8601, so US `MM/DD/YYYY` (and other common statement formats) silently
/// returned null and imported items lost their date. Try ISO first, then the
/// common formats — US month-first before day-first, falling through on an
/// out-of-range month (e.g. `13/04/2024` → day-first).
DateTime? parseImportDate(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final iso = DateTime.tryParse(s);
  if (iso != null) return iso;
  const formats = <String>[
    'MM/dd/yyyy', 'M/d/yyyy', 'MM/dd/yy', 'M/d/yy',
    'MMM d, yyyy', 'MMMM d, yyyy', 'd MMM yyyy',
    'dd-MM-yyyy', 'yyyy/MM/dd', 'dd/MM/yyyy',
  ];
  for (final fmt in formats) {
    try {
      return DateFormat(fmt).parseStrict(s);
    } catch (_) {
      // try the next format
    }
  }
  return null;
}
