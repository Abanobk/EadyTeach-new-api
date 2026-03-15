import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';
import '../../services/api_service.dart';

class AdminInboxScreen extends StatefulWidget {
  const AdminInboxScreen({super.key});
  @override
  State<AdminInboxScreen> createState() => _AdminInboxScreenState();
}

class _AdminInboxScreenState extends State<AdminInboxScreen> {
  List<dynamic> _conversations = [];
  bool _loading = true;
  dynamic _selectedConversation;
  List<dynamic> _messages = [];
  bool _loadingMessages = false;
  final TextEditingController _replyController = TextEditingController();
  final ScrollController _messagesScrollController = ScrollController();
  bool _sending = false;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _replyController.dispose();
    _messagesScrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_messagesScrollController.hasClients) {
        _messagesScrollController.animateTo(
          _messagesScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final input = _statusFilter == 'all' ? <String, dynamic>{} : <String, dynamic>{'status': _statusFilter};
      final res = await ApiService.query('meta.listConversations', input: input);
      final rawData = res['data'];
      setState(() => _conversations = (rawData is List ? rawData : []) as List);
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _openConversation(dynamic conv) async {
    setState(() {
      _selectedConversation = conv;
      _loadingMessages = true;
      _messages = [];
    });
    try {
      final res = await ApiService.query('meta.getConversation', input: {'id': conv['id']});
      final data = res['data'];
      setState(() => _messages = (data is Map ? (data['messages'] ?? []) : []) as List);
      _scrollToBottom();
    } catch (_) {}
    setState(() => _loadingMessages = false);
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _selectedConversation == null) return;
    setState(() => _sending = true);
    try {
      await ApiService.mutate('meta.sendReply', input: {
        'conversationId': _selectedConversation['id'],
        'text': text,
      });
      _replyController.clear();
      await _openConversation(_selectedConversation);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الإرسال: $e'), backgroundColor: Colors.red));
      }
    }
    setState(() => _sending = false);
  }

  Future<void> _convertToLead(dynamic conv) async {
    try {
      await ApiService.mutate('meta.convertToLead', input: {'conversationId': conv['id']});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحويل المحادثة لليد بنجاح'), backgroundColor: Colors.green));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التحويل: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _refreshNames() async {
    try {
      await ApiService.mutate('meta.refreshSenderNames', input: {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث الأسماء بنجاح'), backgroundColor: Colors.green));
      }
      await _load();
    } catch (_) {}
  }

  Future<void> _editConversationName(dynamic conv) async {
    final controller = TextEditingController(text: conv['senderName'] ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppThemeDecorations.cardColor(context),
        title: const Text('تعديل اسم المرسل', style: TextStyle(color: AppColors.text, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.text),
          decoration: InputDecoration(
            hintText: 'اكتب الاسم...',
            hintStyle: const TextStyle(color: AppColors.muted),
            filled: true,
            fillColor: AppThemeDecorations.pageBackground(context),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء', style: TextStyle(color: AppColors.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('حفظ', style: TextStyle(color: AppColors.primary))),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      try {
        await ApiService.mutate('meta.updateConversationName', input: {
          'conversationId': conv['id'],
          'name': name,
        });
        if (_selectedConversation != null && _selectedConversation['id'] == conv['id']) {
          setState(() => _selectedConversation['senderName'] = name);
        }
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التحديث: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  Future<void> _changeConversationStatus(dynamic conv) async {
    final statuses = {'open': 'مفتوح', 'pending': 'معلق', 'resolved': 'محلول'};
    final current = conv['status'] ?? 'open';
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppThemeDecorations.cardColor(context),
        title: const Text('تغيير حالة المحادثة', style: TextStyle(color: AppColors.text, fontSize: 16)),
        children: statuses.entries.map((e) => SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, e.key),
          child: Row(children: [
            Icon(current == e.key ? Icons.radio_button_checked : Icons.radio_button_off, color: AppColors.primary, size: 20),
            const SizedBox(width: 12),
            Text(e.value, style: const TextStyle(color: AppColors.text)),
          ]),
        )).toList(),
      ),
    );
    if (selected != null && selected != current) {
      try {
        await ApiService.mutate('meta.updateConversationStatus', input: {
          'conversationId': conv['id'],
          'status': selected,
        });
        if (_selectedConversation != null && _selectedConversation['id'] == conv['id']) {
          setState(() => _selectedConversation['status'] = selected);
        }
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التحديث: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;
    if (isWide) {
      return Scaffold(
        backgroundColor: AppThemeDecorations.pageBackground(context),
        body: Row(children: [
          SizedBox(width: 340, child: _buildConversationList()),
          const VerticalDivider(width: 1, color: AppColors.border),
          Expanded(child: _buildChatPanel()),
        ]),
      );
    }
    if (_selectedConversation != null) {
      return Scaffold(
        backgroundColor: AppThemeDecorations.pageBackground(context),
        resizeToAvoidBottomInset: true,
        // resizeToAvoidBottomInset يجعل الـ scaffold يتقلص عند ظهور الكيبورد
        appBar: AppBar(
          backgroundColor: AppThemeDecorations.cardColor(context),
          leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => setState(() => _selectedConversation = null)),
          title: GestureDetector(
            onTap: () => _editConversationName(_selectedConversation),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(_selectedConversation['senderName'] ?? _selectedConversation['senderId'] ?? 'محادثة', style: const TextStyle(color: AppColors.text, fontSize: 16), overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 4),
              const Icon(Icons.edit, color: AppColors.muted, size: 14),
            ]),
          ),
          actions: [
            IconButton(icon: const Icon(Icons.more_vert, color: AppColors.text), onPressed: () => _showConversationOptions(_selectedConversation)),
          ],
        ),
        body: _buildChatPanel(),
      );
    }
    return Scaffold(backgroundColor: AppThemeDecorations.pageBackground(context), body: _buildConversationList());
  }

  Widget _buildConversationList() {
    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 48, 16, 12),
        color: AppThemeDecorations.cardColor(context),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('صندوق الرسائل', style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold))),
            IconButton(icon: const Icon(Icons.person_search, color: AppColors.muted, size: 20), tooltip: 'تحديث الأسماء', onPressed: _refreshNames),
            IconButton(icon: const Icon(Icons.refresh, color: AppColors.muted, size: 20), onPressed: _load),
          ]),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _filterChip('all', 'الكل'), const SizedBox(width: 8),
              _filterChip('open', 'مفتوح'), const SizedBox(width: 8),
              _filterChip('resolved', 'محلول'), const SizedBox(width: 8),
              _filterChip('pending', 'معلق'),
            ]),
          ),
        ]),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _conversations.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.inbox_outlined, color: AppColors.muted, size: 64),
                    const SizedBox(height: 16),
                    const Text('لا توجد محادثات', style: TextStyle(color: AppColors.muted, fontSize: 16)),
                  ]))
                : ListView.builder(
                    itemCount: _conversations.length,
                    itemBuilder: (_, i) {
                      final conv = _conversations[i];
                      final isSelected = _selectedConversation?['id'] == conv['id'];
                      final hasLead = conv['leadId'] != null;
                      final senderName = conv['senderName'] ?? conv['senderId'] ?? 'مجهول';
                      final lastMsg = conv['lastMessage'] ?? '';
                      final platform = conv['platform'] ?? 'messenger';
                      final status = conv['status'] ?? 'open';
                      final statusColors = {'open': Colors.green, 'resolved': Colors.blue, 'pending': Colors.orange};
                      final statusLabels = {'open': 'مفتوح', 'resolved': 'محلول', 'pending': 'معلق'};
                      return GestureDetector(
                        onTap: () => _openConversation(conv),
                        onLongPress: () => _showConversationOptions(conv),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary.withOpacity(0.1) : Colors.transparent,
                            border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
                          ),
                          child: Row(children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(22)),
                              child: Center(child: Text(senderName.isNotEmpty ? senderName[0].toUpperCase() : 'M', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 18))),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(senderName, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14), overflow: TextOverflow.ellipsis)),
                                if (hasLead) const Icon(Icons.star, color: AppColors.primary, size: 14),
                              ]),
                              const SizedBox(height: 2),
                              Text(lastMsg.length > 50 ? '${lastMsg.substring(0, 50)}...' : lastMsg, style: const TextStyle(color: AppColors.muted, fontSize: 12), overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Row(children: [
                                GestureDetector(
                                  onTap: () => _changeConversationStatus(conv),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: (statusColors[status] ?? Colors.grey).withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                                    child: Text(statusLabels[status] ?? status, style: TextStyle(color: statusColors[status] ?? Colors.grey, fontSize: 10)),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                                  child: Text(platform, style: const TextStyle(color: Colors.blue, fontSize: 10)),
                                ),
                              ]),
                            ])),
                          ]),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }

  Widget _buildChatPanel() {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    if (_selectedConversation == null) {
      return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.chat_bubble_outline, color: AppColors.muted, size: 64),
        SizedBox(height: 16),
        Text('اختر محادثة لعرضها', style: TextStyle(color: AppColors.muted, fontSize: 16)),
      ]));
    }
    final conv = _selectedConversation;
    final senderName = conv['senderName'] ?? conv['senderId'] ?? 'مجهول';
    final hasLead = conv['leadId'] != null;
    return Column(children: [
      if (MediaQuery.of(context).size.width > 700)
        Container(
          padding: const EdgeInsets.fromLTRB(16, 48, 16, 12),
          color: AppThemeDecorations.cardColor(context),
          child: Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(20)), child: Center(child: Text(senderName.isNotEmpty ? senderName[0].toUpperCase() : 'M', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)))),
            const SizedBox(width: 12),
            Expanded(child: GestureDetector(
              onTap: () => _editConversationName(conv),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(senderName, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit, color: AppColors.muted, size: 14),
                ]),
                Text(conv['platform'] ?? 'messenger', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
            )),
            if (!hasLead)
              TextButton.icon(onPressed: () => _convertToLead(conv), icon: const Icon(Icons.star_border, color: AppColors.primary, size: 18), label: const Text('تحويل لليد', style: TextStyle(color: AppColors.primary, fontSize: 13)))
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.star, color: AppColors.primary, size: 14), SizedBox(width: 4), Text('ليد', style: TextStyle(color: AppColors.primary, fontSize: 12))]),
              ),
          ]),
        ),
      Expanded(
        child: _loadingMessages
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _messages.isEmpty
                ? const Center(child: Text('لا توجد رسائل', style: TextStyle(color: AppColors.muted)))
                : ListView.builder(
                    controller: _messagesScrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final msg = _messages[i];
                      final isFromPage = msg['isFromPage'] == true;
                      return Align(
                        alignment: isFromPage ? Alignment.centerLeft : Alignment.centerRight,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                          decoration: BoxDecoration(
                            color: isFromPage ? AppThemeDecorations.cardColor(context) : AppColors.primary.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isFromPage ? AppColors.border : AppColors.primary.withOpacity(0.3)),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(msg['content'] ?? '', style: const TextStyle(color: AppColors.text, fontSize: 14)),
                            const SizedBox(height: 4),
                            Text(_formatTime(msg['createdAt']), style: const TextStyle(color: AppColors.muted, fontSize: 10)),
                          ]),
                        ),
                      );
                    },
                  ),
      ),
      SafeArea(
        top: false,
        child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(color: AppThemeDecorations.cardColor(context), border: Border(top: BorderSide(color: AppColors.border))),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _replyController,
              style: const TextStyle(color: AppColors.text, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'اكتب ردك...',
                hintStyle: const TextStyle(color: AppColors.muted),
                filled: true, fillColor: AppThemeDecorations.pageBackground(context),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: (_) => _sendReply(),
              onTap: () => _scrollToBottom(),
              maxLines: 4,
              minLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sending ? null : _sendReply,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(22)),
              child: _sending
                  ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)))
                  : const Icon(Icons.send, color: Colors.black, size: 20),
            ),
          ),
        ]),
        ),
      ),
    ]);
  }

  Widget _filterChip(String value, String label) {
    final isSelected = _statusFilter == value;
    return GestureDetector(
      onTap: () { setState(() => _statusFilter = value); _load(); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppThemeDecorations.pageBackground(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.black : AppColors.muted, fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  void _showConversationOptions(dynamic conv) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppThemeDecorations.cardColor(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.muted.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.edit, color: AppColors.primary),
            title: const Text('تعديل اسم المرسل', style: TextStyle(color: AppColors.text)),
            onTap: () { Navigator.pop(ctx); _editConversationName(conv); },
          ),
          ListTile(
            leading: const Icon(Icons.flag, color: Colors.orange),
            title: const Text('تغيير الحالة', style: TextStyle(color: AppColors.text)),
            onTap: () { Navigator.pop(ctx); _changeConversationStatus(conv); },
          ),
          if (conv['leadId'] == null)
            ListTile(
              leading: const Icon(Icons.star_border, color: AppColors.primary),
              title: const Text('تحويل لليد', style: TextStyle(color: AppColors.text)),
              onTap: () { Navigator.pop(ctx); _convertToLead(conv); },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(timestamp is int ? timestamp : int.parse(timestamp.toString()));
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
