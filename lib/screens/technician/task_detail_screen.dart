import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/app_theme.dart';
import '../../services/api_service.dart';

class TaskDetailScreen extends StatefulWidget {
  final Map<String, dynamic> task;
  const TaskDetailScreen({super.key, required this.task});
  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  late Map<String, dynamic> _task;
  late List<Map<String, dynamic>> _items;
  bool _paymentDone = false;
  bool _isLoading = false;
  String _paymentMethod = 'cash';
  final _cashAmountCtrl = TextEditingController();
  File? _transferPhoto;
  final _transferAmountCtrl = TextEditingController();
  String? _estimatedArrival;

  @override
  void initState() {
    super.initState();
    _task = Map<String, dynamic>.from(widget.task);
    final rawItems = _task['items'];
    if (rawItems != null && rawItems is List) {
      _items = rawItems.map<Map<String, dynamic>>((item) {
        if (item is Map) {
          return {'text': item['text']?.toString() ?? item.toString(), 'done': item['done'] == true, 'photos': <File>[]};
        }
        return {'text': item.toString(), 'done': false, 'photos': <File>[]};
      }).toList();
    } else {
      _items = [];
    }
    _estimateArrival();
  }

  void _estimateArrival() {
    final now = DateTime.now();
    final arrival = now.add(const Duration(minutes: 20));
    setState(() => _estimatedArrival = '${arrival.hour.toString().padLeft(2, '0')}:${arrival.minute.toString().padLeft(2, '0')}');
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openWhatsApp(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/2$clean');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openMaps(String address) async {
    final encoded = Uri.encodeComponent(address);
    final uri = Uri.parse('https://maps.google.com/?q=$encoded');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _pickPhoto(int itemIndex, ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 80);
    if (picked != null) setState(() => (_items[itemIndex]['photos'] as List<File>).add(File(picked.path)));
  }

  void _showPhotoSourceDialog(int itemIndex) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        ListTile(leading: const Icon(Icons.camera_alt_outlined, color: AppColors.primary), title: const Text('التقاط صورة', style: TextStyle(color: AppColors.text)), onTap: () { Navigator.pop(context); _pickPhoto(itemIndex, ImageSource.camera); }),
        ListTile(leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary), title: const Text('اختيار من المعرض', style: TextStyle(color: AppColors.text)), onTap: () { Navigator.pop(context); _pickPhoto(itemIndex, ImageSource.gallery); }),
        const SizedBox(height: 8),
      ])),
    );
  }

  Future<void> _pickTransferPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (picked != null) setState(() => _transferPhoto = File(picked.path));
  }

  void _showPaymentSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('تحصيل المبلغ', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 4),
            Text('المبلغ المطلوب: ${_task['amount'] ?? 0} ج.م', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => setS(() => _paymentMethod = 'cash'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _paymentMethod == 'cash' ? AppColors.primary.withOpacity(0.15) : AppColors.bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _paymentMethod == 'cash' ? AppColors.primary : AppColors.border, width: _paymentMethod == 'cash' ? 1.5 : 1),
                  ),
                  child: Column(children: [
                    Icon(Icons.payments_outlined, color: _paymentMethod == 'cash' ? AppColors.primary : AppColors.muted, size: 24),
                    const SizedBox(height: 4),
                    Text('نقداً', style: TextStyle(color: _paymentMethod == 'cash' ? AppColors.primary : AppColors.muted, fontWeight: FontWeight.bold)),
                  ]),
                ),
              )),
              const SizedBox(width: 12),
              Expanded(child: GestureDetector(
                onTap: () => setS(() => _paymentMethod = 'transfer'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _paymentMethod == 'transfer' ? AppColors.primary.withOpacity(0.15) : AppColors.bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _paymentMethod == 'transfer' ? AppColors.primary : AppColors.border, width: _paymentMethod == 'transfer' ? 1.5 : 1),
                  ),
                  child: Column(children: [
                    Icon(Icons.account_balance_outlined, color: _paymentMethod == 'transfer' ? AppColors.primary : AppColors.muted, size: 24),
                    const SizedBox(height: 4),
                    Text('تحويل', style: TextStyle(color: _paymentMethod == 'transfer' ? AppColors.primary : AppColors.muted, fontWeight: FontWeight.bold)),
                  ]),
                ),
              )),
            ]),
            const SizedBox(height: 16),
            if (_paymentMethod == 'cash') ...[
              TextField(
                controller: _cashAmountCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.text),
                decoration: InputDecoration(
                  labelText: 'المبلغ المستلم', labelStyle: const TextStyle(color: AppColors.muted),
                  suffixText: 'ج.م', suffixStyle: const TextStyle(color: AppColors.muted),
                  filled: true, fillColor: AppColors.bg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: () {
                  if (_cashAmountCtrl.text.trim().isEmpty) return;
                  setState(() => _paymentDone = true);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل التحصيل النقدي ✓'), backgroundColor: Colors.green));
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('تحصيل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              )),
            ] else ...[
              GestureDetector(
                onTap: () async { await _pickTransferPhoto(); setS(() {}); },
                child: Container(
                  height: 140, width: double.infinity,
                  decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _transferPhoto == null ? Colors.red.withOpacity(0.5) : Colors.green, width: 1.5)),
                  child: _transferPhoto == null
                      ? Column(mainAxisAlignment: MainAxisAlignment.center, children: const [
                          Icon(Icons.camera_alt_outlined, color: AppColors.primary, size: 32),
                          SizedBox(height: 8),
                          Text('التقط صورة إيصال التحويل (إلزامي)', style: TextStyle(color: AppColors.muted, fontSize: 13), textAlign: TextAlign.center),
                        ])
                      : ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(_transferPhoto!, fit: BoxFit.cover)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _transferAmountCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.text),
                decoration: InputDecoration(
                  labelText: 'المبلغ المحوّل', labelStyle: const TextStyle(color: AppColors.muted),
                  suffixText: 'ج.م', suffixStyle: const TextStyle(color: AppColors.muted),
                  filled: true, fillColor: AppColors.bg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: _transferPhoto == null || _transferAmountCtrl.text.trim().isEmpty ? null : () {
                  setState(() => _paymentDone = true);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل التحويل ✓'), backgroundColor: Colors.green));
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black, disabledBackgroundColor: AppColors.border, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('تحصيل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              )),
            ],
            const SizedBox(height: 8),
          ]),
        ),
      )),
    );
  }

  Future<void> _completeTask() async {
    setState(() => _isLoading = true);
    try {
      await ApiService.mutate('tasks.update', input: {'id': _task['id'], 'status': 'completed'});
      setState(() { _task['status'] = 'completed'; _isLoading = false; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إنهاء المهمة بنجاح ✓'), backgroundColor: Colors.green));
      Navigator.pop(context, true);
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = _task['customerPhone']?.toString() ?? '';
    final address = _task['address']?.toString() ?? '';
    final amount = _task['amount']?.toString() ?? '0';
    final clientName = _task['customerName']?.toString() ?? 'العميل';
    final techName = _task['technicianName']?.toString() ?? '';
    final status = _task['status']?.toString() ?? 'pending';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.card,
          title: Text(_task['title'] ?? 'تفاصيل المهمة', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16)),
          iconTheme: const IconThemeData(color: AppColors.text),
          actions: [
            Container(
              margin: const EdgeInsets.only(left: 12, right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: _statusColor(status).withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
              child: Text(_statusLabel(status), style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── بيانات العميل ──
            _sectionTitle(Icons.person_outline, 'بيانات العميل'),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: _cardDecor(),
              child: Column(children: [
                Row(children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.15), shape: BoxShape.circle), child: const Icon(Icons.person, color: AppColors.primary, size: 24)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(clientName, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16)),
                    if (techName.isNotEmpty) Text('الفني: $techName', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ])),
                ]),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(color: AppColors.border, height: 1),
                  const SizedBox(height: 12),
                  Row(children: [
                    const Icon(Icons.phone_outlined, color: AppColors.muted, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(phone, style: const TextStyle(color: AppColors.text, fontSize: 14))),
                    GestureDetector(
                      onTap: () => _callPhone(phone),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: const [Icon(Icons.call, color: Colors.green, size: 15), SizedBox(width: 4), Text('اتصال', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12))]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _openWhatsApp(phone),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(color: const Color(0xFF25D366).withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: const [Icon(Icons.chat, color: Color(0xFF25D366), size: 15), SizedBox(width: 4), Text('واتساب', style: TextStyle(color: Color(0xFF25D366), fontWeight: FontWeight.bold, fontSize: 12))]),
                      ),
                    ),
                  ]),
                ],
              ]),
            ),
            const SizedBox(height: 12),

            // ── العنوان والموقع ──
            _sectionTitle(Icons.location_on_outlined, 'الموقع'),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: _cardDecor(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.home_outlined, color: AppColors.muted, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(address.isNotEmpty ? address : 'لم يُحدد العنوان', style: const TextStyle(color: AppColors.text, fontSize: 14))),
                ]),
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: OutlinedButton.icon(
                    onPressed: () => _openMaps(address),
                    icon: const Icon(Icons.navigation_outlined, size: 18),
                    label: const Text('توجيه للوجهة'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.primary), padding: const EdgeInsets.symmetric(vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  )),
                ],
              ]),
            ),
            const SizedBox(height: 12),

            // ── المبلغ ووقت الوصول ──
            Row(children: [
              Expanded(child: Container(
                padding: const EdgeInsets.all(14),
                decoration: _cardDecor(),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: const [Icon(Icons.attach_money, color: AppColors.primary, size: 18), SizedBox(width: 6), Text('المبلغ', style: TextStyle(color: AppColors.muted, fontSize: 12))]),
                  const SizedBox(height: 6),
                  Text('$amount ج.م', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 18)),
                ]),
              )),
              const SizedBox(width: 12),
              Expanded(child: Container(
                padding: const EdgeInsets.all(14),
                decoration: _cardDecor(),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: const [Icon(Icons.access_time, color: Colors.blue, size: 18), SizedBox(width: 6), Text('وقت الوصول', style: TextStyle(color: AppColors.muted, fontSize: 12))]),
                  const SizedBox(height: 6),
                  Text(_estimatedArrival ?? '--:--', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 18)),
                  const Text('تقريباً', style: TextStyle(color: AppColors.muted, fontSize: 10)),
                ]),
              )),
            ]),
            const SizedBox(height: 16),

            // ── بنود المهام ──
            if (_items.isNotEmpty) ...[
              _sectionTitle(Icons.checklist_outlined, 'بنود المهمة'),
              ..._items.asMap().entries.map((entry) {
                final i = entry.key;
                final item = entry.value;
                final photos = item['photos'] as List<File>;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: _cardDecor(),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      GestureDetector(
                        onTap: () => _showPhotoSourceDialog(i),
                        child: Container(width: 32, height: 32, decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.add_a_photo_outlined, color: AppColors.primary, size: 18)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(item['text'], style: TextStyle(color: item['done'] ? AppColors.muted : AppColors.text, fontSize: 14, decoration: item['done'] ? TextDecoration.lineThrough : null))),
                      GestureDetector(
                        onTap: () => setState(() => _items[i]['done'] = !item['done']),
                        child: Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(color: item['done'] ? Colors.green.withOpacity(0.2) : AppColors.bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: item['done'] ? Colors.green : AppColors.border, width: 1.5)),
                          child: item['done'] ? const Icon(Icons.check, color: Colors.green, size: 18) : null,
                        ),
                      ),
                    ]),
                    if (photos.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(height: 64, child: ListView(scrollDirection: Axis.horizontal, children: photos.map((f) => Container(margin: const EdgeInsets.only(left: 6), width: 64, height: 64, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(f, fit: BoxFit.cover)))).toList())),
                    ],
                  ]),
                );
              }).toList(),
              const SizedBox(height: 8),
            ],

            // ── زر التحصيل ──
            if (!_paymentDone && status != 'completed') ...[
              _sectionTitle(Icons.payments_outlined, 'التحصيل'),
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                onPressed: _showPaymentSheet,
                icon: const Icon(Icons.payments_outlined, color: Colors.black),
                label: Text('تحصيل $amount ج.م', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black)),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              )),
              const SizedBox(height: 16),
            ],

            // ── زر إنهاء المهمة (بعد التحصيل فقط) ──
            if (_paymentDone && status != 'completed') ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.withOpacity(0.3))),
                child: Row(children: const [Icon(Icons.check_circle_outline, color: Colors.green, size: 20), SizedBox(width: 8), Text('تم تسجيل التحصيل بنجاح', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600))]),
              ),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _completeTask,
                icon: _isLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.task_alt, color: Colors.white),
                label: const Text('إنهاء المهمة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              )),
              const SizedBox(height: 16),
            ],

            if (status == 'completed')
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.withOpacity(0.3))),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.task_alt, color: Colors.green, size: 22), SizedBox(width: 8), Text('تم إنجاز هذه المهمة', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 15))]),
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  BoxDecoration _cardDecor() => BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border));

  Widget _sectionTitle(IconData icon, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [Icon(icon, color: AppColors.primary, size: 18), const SizedBox(width: 6), Text(title, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 14))]),
  );

  Color _statusColor(String status) {
    switch (status) {
      case 'pending': return const Color(0xFFD4920A);
      case 'in_progress': return Colors.blue;
      case 'completed': return Colors.green;
      case 'cancelled': return Colors.red;
      default: return AppColors.muted;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending': return 'جديدة';
      case 'in_progress': return 'جاري التنفيذ';
      case 'completed': return 'مكتملة';
      case 'cancelled': return 'ملغاة';
      default: return status;
    }
  }

  @override
  void dispose() {
    _cashAmountCtrl.dispose();
    _transferAmountCtrl.dispose();
    super.dispose();
  }
}
