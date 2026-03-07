import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../utils/app_theme.dart';
import 'create_quotation_screen.dart';
import 'quotation_detail_screen.dart';

class AdminQuotationsScreen extends StatefulWidget {
  const AdminQuotationsScreen({super.key});

  @override
  State<AdminQuotationsScreen> createState() => _AdminQuotationsScreenState();
}

class _AdminQuotationsScreenState extends State<AdminQuotationsScreen> {
  List<dynamic> _quotations = [];
  bool _loading = true;
  String _filterStatus = 'all';

  final _statusLabels = {
    'all': 'الكل',
    'draft': 'مسودة',
    'sent': 'مُرسل',
    'accepted': 'مقبول',
    'rejected': 'مرفوض',
    'expired': 'منتهي',
  };

  final _statusColors = {
    'draft': Colors.grey,
    'sent': Colors.blue,
    'accepted': Colors.green,
    'rejected': Colors.red,
    'expired': Colors.orange,
  };

  @override
  void initState() {
    super.initState();
    _loadQuotations();
  }

  Future<void> _loadQuotations() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.query('quotations.list');
      setState(() {
        _quotations = res['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل عروض الأسعار: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  List<dynamic> get _filtered {
    if (_filterStatus == 'all') return _quotations;
    return _quotations.where((q) => q['status'] == _filterStatus).toList();
  }

  String _formatDate(dynamic ts) {
    if (ts == null) return '-';
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(ts is int ? ts : int.parse(ts.toString()));
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '-';
    }
  }

  Map<String, int> get _stats {
    final counts = <String, int>{'draft': 0, 'sent': 0, 'accepted': 0, 'rejected': 0};
    for (final q in _quotations) {
      final s = q['status'] as String? ?? 'draft';
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: const Text('عروض الأسعار'),
          backgroundColor: AppColors.card,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.primary),
              onPressed: _loadQuotations,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateQuotationScreen()),
            );
            if (result == true) _loadQuotations();
          },
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          icon: const Icon(Icons.add),
          label: const Text('عرض سعر جديد', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : RefreshIndicator(
                onRefresh: _loadQuotations,
                color: AppColors.primary,
                child: CustomScrollView(
                  slivers: [
                    // Stats
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                _StatChip(label: 'مسودة', count: _stats['draft'] ?? 0, color: Colors.grey),
                                const SizedBox(width: 8),
                                _StatChip(label: 'مُرسل', count: _stats['sent'] ?? 0, color: Colors.blue),
                                const SizedBox(width: 8),
                                _StatChip(label: 'مقبول', count: _stats['accepted'] ?? 0, color: Colors.green),
                                const SizedBox(width: 8),
                                _StatChip(label: 'مرفوض', count: _stats['rejected'] ?? 0, color: Colors.red),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Filter chips
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: _statusLabels.entries.map((e) {
                                  final selected = _filterStatus == e.key;
                                  return Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: FilterChip(
                                      label: Text(e.value),
                                      selected: selected,
                                      onSelected: (_) => setState(() => _filterStatus = e.key),
                                      backgroundColor: AppColors.card,
                                      selectedColor: AppColors.primary.withOpacity(0.2),
                                      checkmarkColor: AppColors.primary,
                                      labelStyle: TextStyle(
                                        color: selected ? AppColors.primary : AppColors.muted,
                                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                                      ),
                                      side: BorderSide(
                                        color: selected ? AppColors.primary : AppColors.border,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // List
                    _filtered.isEmpty
                        ? SliverFillRemaining(
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.request_quote_outlined, size: 64, color: AppColors.muted.withOpacity(0.5)),
                                  const SizedBox(height: 16),
                                  const Text('لا توجد عروض أسعار', style: TextStyle(color: AppColors.muted, fontSize: 16)),
                                  const SizedBox(height: 8),
                                  const Text('اضغط + لإنشاء عرض سعر جديد', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                                ],
                              ),
                            ),
                          )
                        : SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final q = _filtered[index];
                                final status = q['status'] as String? ?? 'draft';
                                final statusColor = _statusColors[status] ?? Colors.grey;
                                final statusLabel = _statusLabels[status] ?? status;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  child: InkWell(
                                    onTap: () async {
                                      final result = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => QuotationDetailScreen(quotationId: q['id']),
                                        ),
                                      );
                                      if (result == true) _loadQuotations();
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: AppColors.card,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: AppColors.border),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: statusColor.withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(20),
                                                  border: Border.all(color: statusColor.withOpacity(0.4)),
                                                ),
                                                child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                                              ),
                                              const Spacer(),
                                              Text(
                                                q['refNumber'] ?? '',
                                                style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              const Icon(Icons.person_outline, size: 14, color: AppColors.muted),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  q['clientName'] ?? q['clientEmail'] ?? 'عميل غير محدد',
                                                  style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              const Icon(Icons.attach_money, size: 14, color: AppColors.muted),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${double.tryParse(q['totalAmount']?.toString() ?? '0')?.toStringAsFixed(0) ?? 0} ج.م',
                                                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 15),
                                              ),
                                              const Spacer(),
                                              const Icon(Icons.calendar_today_outlined, size: 12, color: AppColors.muted),
                                              const SizedBox(width: 4),
                                              Text(
                                                _formatDate(q['createdAt']),
                                                style: const TextStyle(color: AppColors.muted, fontSize: 12),
                                              ),
                                            ],
                                          ),
                                          if (q['notes'] != null && q['notes'].toString().isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              q['notes'].toString(),
                                              style: const TextStyle(color: AppColors.muted, fontSize: 12),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                              childCount: _filtered.length,
                            ),
                          ),
                    const SliverToBoxAdapter(child: SizedBox(height: 80)),
                  ],
                ),
              ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _StatChip({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text('$count', style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w900)),
            Text(label, style: TextStyle(color: color.withOpacity(0.8), fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
