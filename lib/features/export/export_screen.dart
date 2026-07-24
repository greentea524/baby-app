import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import 'csv_export.dart';
import 'export_data.dart';
import 'pdf_export.dart';

/// How far back an export reaches.
enum ExportRange {
  week('Last 7 days', 7),
  month('Last 30 days', 30),
  all('All time', null);

  const ExportRange(this.label, this.days);

  final String label;
  final int? days;
}

/// Export logs as CSV or a PDF summary to share with a pediatrician
/// (KAN-137).
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  ExportRange _range = ExportRange.month;
  bool _busy = false;

  Future<ExportData?> _gather() async {
    final baby = ref.read(currentBabyProvider);
    final feedingRepo = ref.read(feedingRepositoryProvider);
    final diaperRepo = ref.read(diaperRepositoryProvider);
    final growthRepo = ref.read(growthRepositoryProvider);
    if (baby == null ||
        feedingRepo == null ||
        diaperRepo == null ||
        growthRepo == null) {
      return null;
    }

    final now = DateTime.now();
    final end = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 1));
    final start = _range.days == null
        ? DateTime(
            baby.birthDate.year,
            baby.birthDate.month,
            baby.birthDate.day,
          )
        : end.subtract(Duration(days: _range.days!));

    final feedings = await feedingRepo.fetchRange(start, end);
    final diapers = await diaperRepo.fetchRange(start, end);
    final allGrowth = await growthRepo.fetchAll();
    final growth = allGrowth
        .where((m) => !m.date.isBefore(start) && m.date.isBefore(end))
        .toList();

    return ExportData(
      baby: baby,
      start: start,
      end: end,
      feedings: feedings,
      diapers: diapers,
      growth: growth,
    );
  }

  Future<void> _run(bool asPdf) async {
    setState(() => _busy = true);
    try {
      final data = await _gather();
      if (data == null) {
        _snack('No baby selected.');
        return;
      }
      final name = csvFilename(data);
      if (asPdf) {
        final bytes = await buildPdfReport(data);
        await FileSaver.instance.saveFile(
          name: name,
          bytes: bytes,
          fileExtension: 'pdf',
          mimeType: MimeType.pdf,
        );
      } else {
        final bytes = Uint8List.fromList(utf8.encode(buildCsv(data)));
        await FileSaver.instance.saveFile(
          name: name,
          bytes: bytes,
          fileExtension: 'csv',
          mimeType: MimeType.csv,
        );
      }
      _snack(
        data.isEmpty
            ? 'Exported, but no entries in this period.'
            : 'Export ready — check your downloads.',
      );
    } catch (e) {
      _snack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final baby = ref.watch(currentBabyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
      body: baby == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Add a baby on the Home tab to export data.'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Export ${baby.name}\'s logs',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'CSV gives every entry as a spreadsheet. PDF is a summary '
                  'report to share with a pediatrician.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                SegmentedButton<ExportRange>(
                  segments: [
                    for (final r in ExportRange.values)
                      ButtonSegment(value: r, label: Text(r.label)),
                  ],
                  selected: {_range},
                  onSelectionChanged: _busy
                      ? null
                      : (s) => setState(() => _range = s.first),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _run(false),
                  icon: const Icon(Icons.table_chart),
                  label: const Text('Export CSV'),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _run(true),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Export PDF summary'),
                ),
                if (_busy) ...[
                  const SizedBox(height: 24),
                  const Center(child: CircularProgressIndicator()),
                ],
              ],
            ),
    );
  }
}
