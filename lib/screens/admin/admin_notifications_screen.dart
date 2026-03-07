import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import '../../services/api_service.dart';

class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key});
  @override
  State<AdminNotificationsScreen> createState() => _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _target = 'all';
  bool _sending = false;
  bool _loading = false;
  List _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.query('notifications.list');
      final data = res['data'];
      setState(() => _notifications = (data is List ? data : []) as List);
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _markRead(dynamic id) async {
    try {
      await ApiService.mutate('notifications.markRead', input: {'id': id});
      _loadNotifications();
    } catch (_) {}
  }

  Future<void> _markAllRead() async {
    try {
      await ApiService.mutate('notifications.markAllRead');
      _loadNotifications();
    } catch (_) {}
  }

  Future<void> _send() async {
    if (_titleCtrl.text.isEmpty || _bodyCtrl.text.isEmpty) return;
    setState(() => _sending = true);
    try {
      String targetType = 'all';
      String? targetRole;
      if (_target == 'clients') { targetType = 'role'; targetRole = 'client'; }
      else if (_target == 'technicians') { targetType = 'role'; targetRole = 'technician'; }
      final input = <String, dynamic>{
        'title': _titleCtrl.text,
        'message': _bodyCtrl.text,
        'targetType': targetType,
        'linkType': 'none',
        'sendNow': true,
      };
      if (targetRole != null) input['targetRole'] = targetRole;
      await ApiService.mutate('notifications.campaigns.create', input: input);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال الإشعار بنجاح'), backgroundColor: Colors.green));
        _titleCtrl.clear();
        _bodyCtrl.clear();
        _loadNotifications();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الإرسال: $e'), backgroundColor: Colors.red));
    }
    setState(() => _sending = false);
  }

  String _formatTime(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(ts is int ? ts : int.parse(ts.toString()));
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    final unread = _notifications.where((n) => n['isRead'] != true).length;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        iconTheme: const IconThemeData(color: AppColors.text),
        title: Row(children: [
          const Text('الإشعارات', style: TextStyle(color: AppColors.text)),
          if (unread > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
              child: Text('$unread', style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ]),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('قراءة الكل', style: TextStyle(color: AppColors.primary, fontSize: 12)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ─── Send Notification ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('إرسال إشعار جديد', style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text('العنوان', style: TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _titleCtrl,
                style: const TextStyle(color: AppColors.text),
                decoration: InputDecoration(
                  hintText: 'عنوان الإشعار',
                  hintStyle: const TextStyle(color: AppColors.muted),
                  filled: true, fillColor: AppColors.bg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              const Text('الرسالة', style: TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _bodyCtrl,
                maxLines: 3,
                style: const TextStyle(color: AppColors.text),
                decoration: InputDecoration(
                  hintText: 'نص الإشعار...',
                  hintStyle: const TextStyle(color: AppColors.muted),
                  filled: true, fillColor: AppColors.bg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              const Text('إرسال إلى', style: TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _target,
                dropdownColor: AppColors.card,
                style: const TextStyle(color: AppColors.text),
                decoration: InputDecoration(
                  filled: true, fillColor: AppColors.bg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('الجميع')),
                  DropdownMenuItem(value: 'clients', child: Text('العملاء فقط')),
                  DropdownMenuItem(value: 'technicians', child: Text('الفنيون فقط')),
                ],
                onChanged: (v) => setState(() => _target = v!),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.send, color: Colors.black),
                  label: Text(_sending ? 'جاري الإرسال...' : 'إرسال الإشعار'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          // ─── Notifications List ────────────────────────────────────────
          Row(children: [
            const Text('الإشعارات السابقة', style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(onPressed: _loadNotifications, icon: const Icon(Icons.refresh, color: AppColors.muted, size: 20)),
          ]),
          const SizedBox(height: 8),
          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: AppColors.primary),
            ))
          else if (_notifications.isEmpty)
            Center(child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(children: const [
                Icon(Icons.notifications_none, color: AppColors.muted, size: 48),
                SizedBox(height: 8),
                Text('لا توجد إشعارات سابقة', style: TextStyle(color: AppColors.muted)),
              ]),
            ))
          else
            ..._notifications.map((n) {
              final isRead = n['isRead'] == true;
              return GestureDetector(
                onTap: () { if (!isRead) _markRead(n['id']); },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isRead ? AppColors.card : AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isRead ? AppColors.border : AppColors.primary.withOpacity(0.4)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 8, height: 8,
                      margin: const EdgeInsets.only(top: 5, left: 8),
                      decoration: BoxDecoration(
                        color: isRead ? AppColors.muted : AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        n['title'] ?? '',
                        style: TextStyle(
                          color: AppColors.text,
                          fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(n['message'] ?? '', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(_formatTime(n['createdAt']), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                    ])),
                  ]),
                ),
              );
            }).toList(),
        ]),
      ),
    );
  }
}
