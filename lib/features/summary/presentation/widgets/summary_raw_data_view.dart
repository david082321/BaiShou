import 'package:baishou/core/theme/app_theme.dart';
import 'package:baishou/core/widgets/app_toast.dart';
import 'package:baishou/features/summary/domain/services/raw_data_exporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class SummaryRawDataView extends ConsumerStatefulWidget {
  const SummaryRawDataView({super.key});

  @override
  ConsumerState<SummaryRawDataView> createState() => _SummaryRawDataViewState();
}

class _SummaryRawDataViewState extends ConsumerState<SummaryRawDataView> {
  DateTimeRange? _dateRange;
  bool _isExporting = false;

  Future<void> _selectDateRange() async {
    final now = DateTime.now();
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2200),
      initialDateRange:
          _dateRange ??
          DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
      confirmText: '確定',
      cancelText: '取消',
      saveText: '選擇',
    );

    if (result != null) {
      setState(() {
        _dateRange = result;
      });
    }
  }

  Future<void> _exportData() async {
    if (_dateRange == null) {
      AppToast.show(context, '請先選擇日期範圍');
      return;
    }

    setState(() => _isExporting = true);
    try {
      final text = await ref
          .read(rawDataExporterProvider)
          .exportRawData(_dateRange!.start, _dateRange!.end);

      if (text.isEmpty) {
        if (mounted) AppToast.show(context, '該範圍內沒有日記資料');
        return;
      }

      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        AppToast.show(context, '原始資料已複製到剪貼簿', icon: Icons.check);
      }
    } catch (e) {
      if (mounted) AppToast.show(context, '匯出失敗: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '原始資料匯出 (Raw Data Export)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '無損匯出指定日期範圍內的所有日記資料，包含中繼資料和標籤。',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 24),

          // 日期范围选择器
          InkWell(
            onTap: _selectDateRange,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, color: AppTheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _dateRange == null
                          ? '點擊選擇日期範圍'
                          : '${DateFormat('yyyy-MM-dd').format(_dateRange!.start)}  至  ${DateFormat('yyyy-MM-dd').format(_dateRange!.end)}',
                      style: TextStyle(
                        fontSize: 16,
                        color: _dateRange == null ? Colors.grey : null,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          ),

          const Spacer(),

          if (_isExporting)
            const Center(child: CircularProgressIndicator())
          else
            FilledButton.icon(
              onPressed: _dateRange == null ? null : _exportData,
              icon: const Icon(Icons.file_download),
              label: const Text('匯出並複製'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: AppTheme.primary,
              ),
            ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
