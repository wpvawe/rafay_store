import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../providers/auth_provider.dart';
import '../providers/demand_provider.dart';

class ImportService {
  const ImportService._();

  static const _validStatuses = {
    AppConstants.demandPending,
    AppConstants.demandAvailable,
    AppConstants.demandDeferred,
    AppConstants.demandUrgent,
  };

  static const _statusAliases = <String, String>{
    'pending': AppConstants.demandPending,
    'available': AppConstants.demandAvailable,
    'deferred': AppConstants.demandDeferred,
    'urgent': AppConstants.demandUrgent,
  };

  static Future<void> importFromFile(BuildContext context) async {
    final demand = context.read<DemandProvider>();
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx'],
        withData: true,
      );
    } catch (e) {
      if (context.mounted) _snack(context, 'Could not open file picker: $e', isError: true);
      return;
    }

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;

    if (bytes == null || bytes.isEmpty) {
      if (context.mounted) _snack(context, 'Could not read file bytes. Try again.', isError: true);
      return;
    }

    List<List<dynamic>> rows;
    try {
      final ext = (file.extension ?? _sniffExtension(bytes)).toLowerCase();
      rows = ext == 'xlsx' ? _parseExcel(bytes) : _parseCsv(bytes);
    } catch (e) {
      if (context.mounted) _snack(context, 'Failed to parse file: $e', isError: true);
      return;
    }

    final items = _extractItems(rows);

    if (items.isEmpty) {
      if (context.mounted) {
        _snack(context, 'No valid items found. First column must contain item names.');
      }
      return;
    }

    if (context.mounted) {
      await _runWithProgress(context, demand, user, items);
    }
  }

  static Future<void> _runWithProgress(
    BuildContext context,
    DemandProvider demand,
    dynamic user,
    List<(String name, String status)> items,
  ) async {
    final progress = ValueNotifier<double>(0);
    final statusText = ValueNotifier<String>('Starting…');
    final cancelled = ValueNotifier<bool>(false);
    int imported = 0;
    int failed = 0;
    String? firstImportedName;

    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Importing Items'),
          content: SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: statusText,
                  builder: (_, text, __) => Text(text, style: const TextStyle(fontSize: 13)),
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<double>(
                  valueListenable: progress,
                  builder: (_, v, __) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(value: v, minHeight: 8, borderRadius: BorderRadius.circular(4)),
                      const SizedBox(height: 6),
                      Text(
                        '${(v * 100).toStringAsFixed(0)}%  (${(v * items.length).round()} / ${items.length})',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            ValueListenableBuilder<bool>(
              valueListenable: cancelled,
              builder: (_, isCancelled, __) => TextButton.icon(
                icon: Icon(
                  isCancelled ? Icons.hourglass_bottom : Icons.stop_circle_outlined,
                  size: 18,
                  color: isCancelled ? Colors.grey : Colors.red,
                ),
                label: Text(
                  isCancelled ? 'Stopping…' : 'Stop Import',
                  style: TextStyle(color: isCancelled ? Colors.grey : Colors.red),
                ),
                onPressed: isCancelled
                    ? null
                    : () {
                        cancelled.value = true;
                        statusText.value = 'Stopping…';
                      },
              ),
            ),
          ],
        ),
      ),
    );

    for (int i = 0; i < items.length; i++) {
      if (cancelled.value) break;
      final (name, status) = items[i];
      statusText.value = 'Adding: $name';
      await demand.addItem(
        name: name,
        quantity: '1',
        unit: 'Piece',
        notes: '',
        addedBy: user,
        status: status,
        suppressNotification: true,
      );
      if (demand.error == null) {
        firstImportedName ??= name;
        imported++;
      } else {
        failed++;
        demand.clearError();
      }
      progress.value = (i + 1) / items.length;
    }

    if (imported > 0 && firstImportedName != null) {
      await demand.sendBulkAddNotification(
        firstItemName: firstImportedName,
        itemCount: imported,
      );
    }

    final wasCancelled = cancelled.value;
    if (wasCancelled) {
      statusText.value = 'Stopped. $imported imported so far.';
    } else {
      statusText.value = failed == 0
          ? '✓ Done! Imported $imported item${imported == 1 ? '' : 's'}.'
          : 'Done. $imported imported, $failed failed.';
      progress.value = 1.0;
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));

    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    await dialogFuture;

    if (context.mounted) {
      if (wasCancelled) {
        _snack(context, 'Import stopped. $imported item${imported == 1 ? '' : 's'} added.');
      } else if (failed == 0) {
        _snack(context, '✓ Successfully imported $imported item${imported == 1 ? '' : 's'}.');
      } else {
        _snack(context, 'Imported $imported / ${items.length} items. $failed failed.', isError: true);
      }
    }
  }

  static String _sniffExtension(Uint8List bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0x50 && bytes[1] == 0x4B &&
        bytes[2] == 0x03 && bytes[3] == 0x04) return 'xlsx';
    return 'csv';
  }

  static List<List<dynamic>> _parseCsv(Uint8List bytes) {
    final stripped = bytes.length >= 3 &&
            bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF
        ? bytes.sublist(3)
        : bytes;
    final raw = utf8.decode(stripped, allowMalformed: true);
    final normalised = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    try {
      return const CsvToListConverter(eol: '\n').convert(normalised);
    } catch (_) {
      return const CsvToListConverter().convert(normalised);
    }
  }

  static List<List<dynamic>> _parseExcel(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final sharedStrings = <String>[];
    final ssFile = archive.findFile('xl/sharedStrings.xml');
    if (ssFile != null) {
      try {
        final xml = utf8.decode(ssFile.content as List<int>, allowMalformed: true);
        final siPat = RegExp(r'<si>(.*?)</si>', dotAll: true);
        final tPat = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true);
        for (final siM in siPat.allMatches(xml)) {
          final parts = tPat.allMatches(siM.group(1) ?? '').map((m) => _unescapeXml(m.group(1) ?? '')).join();
          sharedStrings.add(parts);
        }
      } catch (_) {}
    }

    final sheetFiles = archive.files
        .where((f) => f.isFile && f.name.startsWith('xl/worksheets/sheet') && f.name.endsWith('.xml'))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (sheetFiles.isEmpty) return [];

    final sheetXml = utf8.decode(sheetFiles.first.content as List<int>, allowMalformed: true);
    final result = <List<dynamic>>[];
    final rowPat = RegExp(r'<row\b[^>]*>(.*?)</row>', dotAll: true);
    final cellPat = RegExp(r'<c\b([^>]*)>(.*?)</c>', dotAll: true);
    final vPat = RegExp(r'<v[^>]*>(.*?)</v>', dotAll: true);
    final isPat = RegExp(r'<is>(.*?)</is>', dotAll: true);
    final tPat = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true);

    for (final rowM in rowPat.allMatches(sheetXml)) {
      final cells = <String>[];
      for (final cellM in cellPat.allMatches(rowM.group(1) ?? '')) {
        final attrs = cellM.group(1) ?? '';
        final inner = cellM.group(2) ?? '';
        final rM = RegExp(r'\br="([A-Z]+)\d+"').firstMatch(attrs);
        if (rM != null) {
          final colIdx = _colToIndex(rM.group(1)!);
          while (cells.length < colIdx) cells.add('');
        }
        final typeM = RegExp(r'\bt="([^"]*)"').firstMatch(attrs);
        final cellType = typeM?.group(1) ?? '';
        final String value;
        if (cellType == 's') {
          final vM = vPat.firstMatch(inner);
          final idx = int.tryParse(vM?.group(1)?.trim() ?? '') ?? -1;
          value = (idx >= 0 && idx < sharedStrings.length) ? sharedStrings[idx] : '';
        } else if (cellType == 'inlineStr') {
          final isM = isPat.firstMatch(inner);
          value = tPat.allMatches(isM?.group(1) ?? '').map((m) => _unescapeXml(m.group(1) ?? '')).join();
        } else if (cellType == 'b') {
          value = (vPat.firstMatch(inner)?.group(1)?.trim() == '1') ? 'true' : 'false';
        } else {
          value = vPat.firstMatch(inner)?.group(1)?.trim() ?? '';
        }
        cells.add(value);
      }
      if (cells.any((c) => c.isNotEmpty)) result.add(cells);
    }
    return result;
  }

  static int _colToIndex(String col) {
    int idx = 0;
    for (final cu in col.codeUnits) {
      idx = idx * 26 + (cu - 65 + 1);
    }
    return idx - 1;
  }

  static String _unescapeXml(String s) {
    final decoded = s.replaceAllMapped(
      RegExp(r'&#([xX][0-9A-Fa-f]+|[0-9]+);'),
      (m) {
        final raw = m.group(1)!;
        final cp = raw.startsWith('x') || raw.startsWith('X')
            ? int.tryParse(raw.substring(1), radix: 16)
            : int.tryParse(raw);
        if (cp == null) return m.group(0)!;
        return String.fromCharCode(cp);
      },
    );
    return decoded
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#10;', '\n');
  }

  static List<(String name, String status)> _extractItems(List<List<dynamic>> rows) {
    final out = <(String, String)>[];
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;
      final rawName = (row[0]?.toString() ?? '').trim();
      if (rawName.isEmpty) continue;
      if (i == 0) {
        final lower = rawName.toLowerCase();
        if (lower == 'name' || lower == 'item' || lower == 'item name' ||
            lower == 'product' || lower == 'product name') continue;
      }
      String status = AppConstants.demandPending;
      if (row.length > 1) {
        final rawStatus = (row[1]?.toString() ?? '').trim().toLowerCase();
        if (_validStatuses.contains(rawStatus)) {
          status = rawStatus;
        } else if (_statusAliases.containsKey(rawStatus)) {
          status = _statusAliases[rawStatus]!;
        }
      }
      out.add((rawName, status));
    }
    return out;
  }

  static void _snack(BuildContext context, String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        duration: const Duration(seconds: 4),
      ));
  }
}
