import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';

class TechnicianCustodyScreen extends StatefulWidget {
  const TechnicianCustodyScreen({super.key});
  @override
  State<TechnicianCustodyScreen> createState() => _TechnicianCustodyScreenState();
}

class _TechnicianCustodyScreenState extends State<TechnicianCustodyScreen> {
  bool _loading = true;
  Map<String, dynamic> _custody = {};
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _expenseCategories = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.query('acc.getTechnicianCustody', input: {}),
        ApiService.query('acc.getTransactions', input: {'limit': 50}),
        ApiService.query('acc.getExpenseCategories'),
      ]);
      setState(() {
        _custody = Map<String, dynamic>.from(results[0]['data'] ?? {});
        final allTx = (results[1]['data'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        final myId = _custody['technicianId'];
        _transactions = myId != null
            ? allTx.where((t) => t['technicianId'] == myId).toList()
            : allTx;
        _expenseCategories = (results[2]['data'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'collection': return Colors.green;
      case 'expense': return Colors.red;
      case 'advance': return Colors.blue;
      case 'settlement': return Colors.orange;
      case 'adjustment': return Colors.purple;
      default: return AppColors.muted;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'collection': return 'تحصيل';
      case 'expense': return 'مصروف';
      case 'advance': return 'سلفة';
      case 'settlement': return 'تسليم عهدة';
      case 'adjustment': return 'تسوية';
      default: return type;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'collection': return Icons.arrow_downward;
      case 'expense': return Icons.arrow_upward;
      case 'advance': return Icons.account_balance_wallet;
      case 'settlement': return Icons.handshake;
      case 'adjustment': return Icons.swap_vert;
      default: return Icons.receipt;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved': return 'معتمد';
      case 'pending': return 'في الانتظار';
      case 'rejected': return 'مرفوض';
      default: return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved': return Colors.green;
      case 'pending': return Colors.orange;
      case 'rejected': return Colors.red;
      default: return AppColors.muted;
    }
  }

  String _formatAmount(dynamic amount) {
    final num = double.tryParse(amount.toString()) ?? 0;
    if (num == num.roundToDouble()) return '${num.round()} ج.م';
    return '${num.toStringAsFixed(2)} ج.م';
  }

  String _formatDate(String? dt) {
    if (dt == null) return '—';
    try {
      final d = DateTime.parse(dt);
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return dt.length > 10 ? dt.substring(0, 10) : dt;
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = (_custody['balance'] as num? ?? 0).toDouble();
    final totalIn = (_custody['totalIn'] as num? ?? 0).toDouble();
    final totalOut = (_custody['totalOut'] as num? ?? 0).toDouble();
    final pending = (_custody['pendingExpenses'] as num? ?? 0).toDouble();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppThemeDecorations.pageBackground(context),
        appBar: AppBar(
          backgroundColor: AppThemeDecorations.cardColor(context),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.primary, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('عهدتي', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
          actions: [
            IconButton(icon: const Icon(Icons.refresh, color: AppColors.muted), onPressed: _loadData),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showAddExpense,
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('تسجيل مصروف', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : RefreshIndicator(
                onRefresh: _loadData,
                color: AppColors.primary,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Balance card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: balance > 0
                              ? [Colors.orange, Colors.orange.shade700]
                              : [Colors.green, Colors.green.shade700],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(children: [
                        const Text('رصيد العهدة الحالي', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          _formatAmount(balance),
                          style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900),
                        ),
                        if (balance > 0)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text('مطلوب تسليم هذا المبلغ', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 16),

                    // Summary row
                    Row(children: [
                      _summaryCard('إجمالي الوارد', totalIn, Colors.green, Icons.arrow_downward),
                      const SizedBox(width: 10),
                      _summaryCard('إجمالي الصادر', totalOut, Colors.red, Icons.arrow_upward),
                    ]),
                    const SizedBox(height: 10),
                    if (pending > 0)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.hourglass_bottom, color: Colors.orange, size: 18),
                          const SizedBox(width: 8),
                          Text('مصروفات معلقة: ${_formatAmount(pending)}',
                              style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13)),
                        ]),
                      ),
                    const SizedBox(height: 20),

                    // Transactions
                    const Text('سجل الحركات', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 10),

                    if (_transactions.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('لا توجد حركات بعد', style: TextStyle(color: AppColors.muted)),
                        ),
                      )
                    else
                      ..._transactions.map((tx) {
                        final type = tx['type'] ?? '';
                        final isIncome = type == 'collection' || type == 'advance';
                        final status = tx['status'] ?? 'approved';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppThemeDecorations.cardColor(context),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: status == 'rejected'
                                  ? Colors.red.withOpacity(0.3)
                                  : status == 'pending'
                                      ? Colors.orange.withOpacity(0.3)
                                      : AppColors.border,
                            ),
                          ),
                          child: Row(children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: _typeColor(type).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(_typeIcon(type), color: _typeColor(type), size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Text(_typeLabel(type),
                                    style: TextStyle(color: _typeColor(type), fontWeight: FontWeight.bold, fontSize: 12)),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: _statusColor(status).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(_statusLabel(status),
                                      style: TextStyle(color: _statusColor(status), fontSize: 9, fontWeight: FontWeight.bold)),
                                ),
                              ]),
                              if ((tx['description'] ?? '').toString().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(tx['description'], style: const TextStyle(color: AppColors.muted, fontSize: 11),
                                      maxLines: 2, overflow: TextOverflow.ellipsis),
                                ),
                              if (tx['rejectionNote'] != null && tx['rejectionNote'].toString().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text('سبب الرفض: ${tx['rejectionNote']}',
                                      style: const TextStyle(color: Colors.red, fontSize: 10)),
                                ),
                              Text(_formatDate(tx['createdAt']?.toString()),
                                  style: const TextStyle(color: AppColors.muted, fontSize: 10)),
                            ])),
                            Text(
                              '${isIncome ? '+' : '-'}${_formatAmount(tx['amount'])}',
                              style: TextStyle(
                                color: isIncome ? Colors.green : Colors.red,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                decoration: status == 'rejected' ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ]),
                        );
                      }),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _summaryCard(String label, double value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppThemeDecorations.cardColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
            Text(_formatAmount(value),
                style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 14)),
          ])),
        ]),
      ),
    );
  }

  void _showAddExpense() {
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String? selectedCategory;
    Uint8List? receiptBytes;
    String? receiptFileName;
    bool uploading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setS) => Container(
            decoration: BoxDecoration(
              color: AppThemeDecorations.cardColor(ctx),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                const Text('تسجيل مصروف جديد', style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('المصروف هيتبعت للمسؤول للاعتماد', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 20),

                const Text('المبلغ (ج.م)', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.text, fontSize: 22, fontWeight: FontWeight.bold),
                  decoration: _inputDec(hint: '0.00'),
                ),
                const SizedBox(height: 16),

                const Text('تصنيف المصروف', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: _expenseCategories.map((c) {
                  final sel = selectedCategory == c['name'];
                  return GestureDetector(
                    onTap: () => setS(() => selectedCategory = c['name']),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? Colors.red.withOpacity(0.15) : AppThemeDecorations.pageBackground(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: sel ? Colors.red : AppColors.border),
                      ),
                      child: Text(c['name'], style: TextStyle(
                          color: sel ? Colors.red : AppColors.muted,
                          fontWeight: sel ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
                    ),
                  );
                }).toList()),
                const SizedBox(height: 16),

                const Text('الوصف', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  style: const TextStyle(color: AppColors.text),
                  decoration: _inputDec(hint: 'مثال: شراء موصلات HDMI عدد 3'),
                ),
                const SizedBox(height: 16),

                // Receipt image upload
                const Text('صورة الإيصال (اختياري)', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 8),
                _ReceiptPicker(
                  receiptBytes: receiptBytes,
                  onPick: () async {
                    final picker = ImagePicker();
                    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 80);
                    if (picked == null) return;
                    final bytes = await picked.readAsBytes();
                    setS(() {
                      receiptBytes = bytes;
                      receiptFileName = picked.name;
                    });
                  },
                  onRemove: () => setS(() { receiptBytes = null; receiptFileName = null; }),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: uploading ? null : () async {
                      if (amountCtrl.text.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('أدخل المبلغ'), backgroundColor: Colors.red));
                        return;
                      }
                      setS(() => uploading = true);

                      String? receiptUrl;
                      try {
                        if (receiptBytes != null) {
                          receiptUrl = await ApiService.uploadFile(
                            '',
                            bytes: receiptBytes!,
                            filename: receiptFileName ?? 'receipt_${DateTime.now().millisecondsSinceEpoch}.jpg',
                          );
                        }

                        await ApiService.mutate('acc.createTransaction', input: {
                          'type': 'expense',
                          'technicianId': _custody['technicianId'],
                          'amount': double.tryParse(amountCtrl.text) ?? 0,
                          'description': descCtrl.text.trim(),
                          'category': selectedCategory,
                          if (receiptUrl != null) 'receiptUrl': receiptUrl,
                        });

                        if (ctx.mounted) Navigator.pop(ctx);
                        _loadData();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم تسجيل المصروف – في انتظار اعتماد المسؤول'),
                                backgroundColor: Colors.orange,
                              ));
                        }
                      } catch (e) {
                        setS(() => uploading = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: uploading
                        ? const SizedBox(height: 20, width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('تسجيل المصروف', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  ),
                ),
              ],
            )),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDec({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
      filled: true,
      fillColor: AppThemeDecorations.pageBackground(context),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}

class _ReceiptPicker extends StatelessWidget {
  final Uint8List? receiptBytes;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _ReceiptPicker({
    required this.receiptBytes,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (receiptBytes != null) {
      return Column(
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(receiptBytes!, height: 160, width: double.infinity, fit: BoxFit.cover),
              ),
              Positioned(
                top: 6,
                left: 6,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('تغيير الصورة', style: TextStyle(fontSize: 12)),
          ),
        ],
      );
    }
    return GestureDetector(
      onTap: onPick,
      child: Container(
        height: 100,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppThemeDecorations.pageBackground(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined, color: AppColors.muted, size: 32),
            SizedBox(height: 6),
            Text('اضغط لرفع صورة الإيصال', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
