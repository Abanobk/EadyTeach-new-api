import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';
import '../../services/api_service.dart';
import 'crm_lead_detail_screen.dart';

class AdminCrmScreen extends StatefulWidget {
  const AdminCrmScreen({super.key});
  @override
  State<AdminCrmScreen> createState() => _AdminCrmScreenState();
}

class _AdminCrmScreenState extends State<AdminCrmScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _leads = [];
  List<dynamic> _staff = [];
  Map<String, dynamic> _stats = {};
  bool _loading = false;
  String _stageFilter = 'all';
  String _assigneeFilter = 'all';
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  static const _stages = [
    {'key': 'new', 'label': 'جديد', 'icon': Icons.fiber_new, 'color': Colors.blue},
    {'key': 'contacted', 'label': 'تم التواصل', 'icon': Icons.phone_callback, 'color': Colors.cyan},
    {'key': 'qualified', 'label': 'مؤهل', 'icon': Icons.verified, 'color': Colors.purple},
    {'key': 'proposal', 'label': 'عرض سعر', 'icon': Icons.description, 'color': Colors.orange},
    {'key': 'negotiation', 'label': 'تفاوض', 'icon': Icons.handshake, 'color': Colors.amber},
    {'key': 'won', 'label': 'تم البيع', 'icon': Icons.emoji_events, 'color': Colors.green},
    {'key': 'lost', 'label': 'مفقود', 'icon': Icons.cancel, 'color': Colors.red},
  ];

  static const _priorityColors = {'high': Colors.red, 'medium': Colors.orange, 'low': Colors.green};
  static const _priorityLabels = {'high': 'عالي', 'medium': 'متوسط', 'low': 'منخفض'};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final futures = await Future.wait([
        ApiService.query('crm.getLeads', input: _buildFilters()),
        ApiService.query('crm.getStats'),
        ApiService.query('crm.getStaffList'),
      ]);
      setState(() {
        _leads = (futures[0]['data'] is List ? futures[0]['data'] : []) as List;
        _stats = (futures[1]['data'] is Map ? futures[1]['data'] : {}) as Map<String, dynamic>;
        _staff = (futures[2]['data'] is List ? futures[2]['data'] : []) as List;
      });
    } catch (_) {}
    setState(() => _loading = false);
  }

  Map<String, dynamic> _buildFilters() {
    final f = <String, dynamic>{};
    if (_stageFilter != 'all') f['stage'] = _stageFilter;
    if (_assigneeFilter != 'all') f['assignedTo'] = int.tryParse(_assigneeFilter);
    if (_searchQuery.isNotEmpty) f['search'] = _searchQuery;
    return f;
  }

  Future<void> _loadLeads() async {
    try {
      final res = await ApiService.query('crm.getLeads', input: _buildFilters());
      setState(() => _leads = (res['data'] is List ? res['data'] : []) as List);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeDecorations.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppThemeDecorations.cardColor(context),
        title: const Text('إدارة العملاء CRM', style: TextStyle(color: AppColors.text, fontSize: 17)),
        iconTheme: const IconThemeData(color: AppColors.text),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _loadAll),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.muted,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.dashboard, size: 18), text: 'لوحة التحكم'),
            Tab(icon: Icon(Icons.view_kanban, size: 18), text: 'خط الأنابيب'),
            Tab(icon: Icon(Icons.list_alt, size: 18), text: 'كل الليدز'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(controller: _tabController, children: [
              _buildDashboard(),
              _buildPipeline(),
              _buildLeadsList(),
            ]),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: _showCreateLead,
        child: const Icon(Icons.person_add, color: Colors.black),
      ),
    );
  }

  // ─── Dashboard ──────────────────────────────────────────────
  Widget _buildDashboard() {
    final total = _stats['total'] ?? 0;
    final byStage = (_stats['byStage'] ?? {}) as Map;
    final byAssignee = (_stats['byAssignee'] ?? []) as List;
    final totalValue = (_stats['totalValue'] ?? 0).toDouble();
    final wonValue = (_stats['wonValue'] ?? 0).toDouble();
    final recentActivities = (_stats['recentActivities'] ?? []) as List;

    return RefreshIndicator(
      onRefresh: _loadAll,
      color: AppColors.primary,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        // Stats Cards Row
        Wrap(spacing: 10, runSpacing: 10, children: [
          _statCard('إجمالي الليدز', '$total', Icons.people, Colors.blue),
          _statCard('تم البيع', '${byStage['won'] ?? 0}', Icons.emoji_events, Colors.green),
          _statCard('قيد التفاوض', '${(byStage['negotiation'] ?? 0) + (byStage['proposal'] ?? 0)}', Icons.handshake, Colors.orange),
          _statCard('القيمة المتوقعة', '${totalValue.toStringAsFixed(0)} ج.م', Icons.attach_money, AppColors.primary),
        ]),
        const SizedBox(height: 20),

        // Pipeline overview
        const Text('خط الأنابيب', style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        ...(_stages.map((s) {
          final count = byStage[s['key']] ?? 0;
          final pct = total > 0 ? count / total : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () {
                setState(() => _stageFilter = s['key'] as String);
                _tabController.animateTo(2);
                _loadLeads();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: AppThemeDecorations.cardColor(context), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  Icon(s['icon'] as IconData, color: s['color'] as Color, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s['label'] as String, style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: pct, backgroundColor: AppThemeDecorations.pageBackground(context), color: s['color'] as Color, minHeight: 6),
                    ),
                  ])),
                  const SizedBox(width: 10),
                  Text('$count', style: TextStyle(color: s['color'] as Color, fontWeight: FontWeight.bold, fontSize: 16)),
                ]),
              ),
            ),
          );
        })),
        const SizedBox(height: 20),

        // By Assignee
        if (byAssignee.isNotEmpty) ...[
          const Text('توزيع المناديب', style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...byAssignee.map((a) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: AppThemeDecorations.cardColor(context), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(18)),
                child: Center(child: Text((a['name'] ?? 'غ')[0], style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold))),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(a['name'] ?? 'غير موزع', style: const TextStyle(color: AppColors.text, fontSize: 13))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                child: Text('${a['count']}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ]),
          )),
          const SizedBox(height: 20),
        ],

        // Recent Activities
        if (recentActivities.isNotEmpty) ...[
          const Text('آخر النشاطات', style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...recentActivities.take(10).map((a) => _activityTile(a)),
        ],
      ]),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      width: MediaQuery.of(context).size.width > 500 ? 170 : (MediaQuery.of(context).size.width - 42) / 2,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppThemeDecorations.cardColor(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
      ]),
    );
  }

  Widget _activityTile(dynamic a) {
    final typeIcons = {
      'note': Icons.note, 'call': Icons.phone, 'meeting': Icons.groups,
      'email': Icons.email, 'stage_change': Icons.swap_horiz, 'assignment': Icons.person_add,
      'created': Icons.add_circle, 'follow_up': Icons.schedule, 'other': Icons.more_horiz,
    };
    final typeColors = {
      'note': Colors.blue, 'call': Colors.green, 'meeting': Colors.purple,
      'email': Colors.cyan, 'stage_change': Colors.orange, 'assignment': AppColors.primary,
      'created': Colors.teal, 'follow_up': Colors.amber, 'other': Colors.grey,
    };
    final type = a['type'] ?? 'note';
    return GestureDetector(
      onTap: () {
        if (a['leadId'] != null) _openLeadDetail(a['leadId']);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: AppThemeDecorations.cardColor(context), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border.withOpacity(0.5))),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: (typeColors[type] ?? Colors.grey).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: Icon(typeIcons[type] ?? Icons.circle, color: typeColors[type] ?? Colors.grey, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a['title'] ?? '', style: const TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w600)),
            Text('${a['leadName'] ?? ''} • ${a['userName'] ?? ''}', style: const TextStyle(color: AppColors.muted, fontSize: 10)),
          ])),
          Text(_formatDate(a['createdAt']), style: const TextStyle(color: AppColors.muted, fontSize: 9)),
        ]),
      ),
    );
  }

  // ─── Pipeline (Kanban-like horizontal scroll) ───────────────
  Widget _buildPipeline() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      color: AppColors.primary,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _stages.map((stage) {
            final stageLeads = _leads.where((l) => (l['pipelineStage'] ?? 'new') == stage['key']).toList();
            return Container(
              width: 260,
              margin: const EdgeInsets.only(right: 10),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: (stage['color'] as Color).withOpacity(0.15),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                    border: Border(bottom: BorderSide(color: stage['color'] as Color, width: 2)),
                  ),
                  child: Row(children: [
                    Icon(stage['icon'] as IconData, color: stage['color'] as Color, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(stage['label'] as String, style: TextStyle(color: stage['color'] as Color, fontWeight: FontWeight.bold, fontSize: 13))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: (stage['color'] as Color).withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                      child: Text('${stageLeads.length}', style: TextStyle(color: stage['color'] as Color, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ]),
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppThemeDecorations.cardColor(context).withOpacity(0.5),
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                    ),
                    child: stageLeads.isEmpty
                        ? const Center(child: Text('فارغ', style: TextStyle(color: AppColors.muted, fontSize: 12)))
                        : ListView.builder(
                            padding: const EdgeInsets.all(6),
                            itemCount: stageLeads.length,
                            itemBuilder: (_, i) => _pipelineCard(stageLeads[i], stage),
                          ),
                  ),
                ),
              ]),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _pipelineCard(dynamic lead, Map<String, dynamic> stage) {
    final priority = lead['priority'] ?? 'medium';
    return GestureDetector(
      onTap: () => _openLeadDetail(lead['id']),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppThemeDecorations.cardColor(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(lead['name'] ?? '', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(color: _priorityColors[priority] ?? Colors.grey, shape: BoxShape.circle),
            ),
          ]),
          if ((lead['phone'] ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(lead['phone'], style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ),
          const SizedBox(height: 6),
          Row(children: [
            if (lead['assigneeName'] != null && (lead['assigneeName'] as String).isNotEmpty) ...[
              Icon(Icons.person, color: AppColors.muted, size: 12),
              const SizedBox(width: 2),
              Expanded(child: Text(lead['assigneeName'], style: const TextStyle(color: AppColors.muted, fontSize: 10), overflow: TextOverflow.ellipsis)),
            ] else
              const Expanded(child: Text('غير موزع', style: TextStyle(color: AppColors.muted, fontSize: 10, fontStyle: FontStyle.italic))),
            if ((lead['expectedValue'] ?? 0) > 0)
              Text('${(lead['expectedValue'] as num).toStringAsFixed(0)} ج.م', style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold)),
          ]),
        ]),
      ),
    );
  }

  // ─── Leads List ─────────────────────────────────────────────
  Widget _buildLeadsList() {
    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        color: AppThemeDecorations.cardColor(context),
        child: Column(children: [
          TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: AppColors.text, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'بحث بالاسم أو الهاتف...',
              hintStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: AppColors.muted, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear, size: 18, color: AppColors.muted), onPressed: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); _loadLeads(); })
                  : null,
              filled: true, fillColor: AppThemeDecorations.pageBackground(context),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onSubmitted: (v) { setState(() => _searchQuery = v.trim()); _loadLeads(); },
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _stageChip('all', 'الكل', null),
              ..._stages.map((s) => _stageChip(s['key'] as String, s['label'] as String, s['color'] as Color)),
            ]),
          ),
          const SizedBox(height: 6),
          if (_staff.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _assigneeChip('all', 'كل المناديب'),
                ..._staff.map((s) => _assigneeChip('${s['id']}', s['name'] ?? '')),
              ]),
            ),
        ]),
      ),
      Expanded(
        child: _leads.isEmpty
            ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.people_outline, color: AppColors.muted, size: 64),
                SizedBox(height: 16),
                Text('لا يوجد ليدز', style: TextStyle(color: AppColors.muted)),
              ]))
            : RefreshIndicator(
                onRefresh: _loadAll,
                color: AppColors.primary,
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _leads.length,
                  itemBuilder: (_, i) => _leadListTile(_leads[i]),
                ),
              ),
      ),
    ]);
  }

  Widget _stageChip(String key, String label, Color? color) {
    final selected = _stageFilter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () { setState(() => _stageFilter = key); _loadLeads(); },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? (color ?? AppColors.primary) : AppThemeDecorations.pageBackground(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? (color ?? AppColors.primary) : AppColors.border),
          ),
          child: Text(label, style: TextStyle(color: selected ? Colors.black : AppColors.muted, fontSize: 11, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
        ),
      ),
    );
  }

  Widget _assigneeChip(String key, String label) {
    final selected = _assigneeFilter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () { setState(() => _assigneeFilter = key); _loadLeads(); },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withOpacity(0.2) : AppThemeDecorations.pageBackground(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? AppColors.primary : AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.person, size: 12, color: AppColors.muted),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: selected ? AppColors.primary : AppColors.muted, fontSize: 11)),
          ]),
        ),
      ),
    );
  }

  Widget _leadListTile(dynamic lead) {
    final stage = lead['pipelineStage'] ?? 'new';
    final stageInfo = _stages.firstWhere((s) => s['key'] == stage, orElse: () => _stages.first);
    final priority = lead['priority'] ?? 'medium';

    return GestureDetector(
      onTap: () => _openLeadDetail(lead['id']),
      onLongPress: () => _showLeadActions(lead),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppThemeDecorations.cardColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: (stageInfo['color'] as Color).withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
              child: Center(child: Text((lead['name'] ?? 'ل')[0].toUpperCase(), style: TextStyle(color: stageInfo['color'] as Color, fontWeight: FontWeight.bold, fontSize: 16))),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(lead['name'] ?? '', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14)),
              if ((lead['phone'] ?? '').isNotEmpty)
                Text(lead['phone'], style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: (stageInfo['color'] as Color).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                child: Text(stageInfo['label'] as String, style: TextStyle(color: stageInfo['color'] as Color, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 4),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: _priorityColors[priority] ?? Colors.grey, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(_priorityLabels[priority] ?? '', style: const TextStyle(color: AppColors.muted, fontSize: 9)),
              ]),
            ]),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.person_outline, size: 14, color: AppColors.muted),
            const SizedBox(width: 4),
            Expanded(child: Text(
              (lead['assigneeName'] != null && (lead['assigneeName'] as String).isNotEmpty) ? lead['assigneeName'] : 'غير موزع',
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            )),
            if ((lead['expectedValue'] ?? 0) > 0)
              Text('${(lead['expectedValue'] as num).toStringAsFixed(0)} ج.م', style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Text(lead['source'] ?? '', style: TextStyle(color: lead['source'] == 'messenger' ? Colors.blue : AppColors.muted, fontSize: 10)),
          ]),
        ]),
      ),
    );
  }

  // ─── Actions ────────────────────────────────────────────────
  void _openLeadDetail(dynamic id) async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => CrmLeadDetailScreen(leadId: id is int ? id : int.parse(id.toString()), staff: _staff)));
    if (result == true) _loadAll();
  }

  void _showLeadActions(dynamic lead) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppThemeDecorations.cardColor(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.muted.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 12),
        ListTile(
          leading: const Icon(Icons.open_in_new, color: AppColors.primary),
          title: const Text('فتح التفاصيل', style: TextStyle(color: AppColors.text)),
          onTap: () { Navigator.pop(ctx); _openLeadDetail(lead['id']); },
        ),
        ListTile(
          leading: const Icon(Icons.person_add, color: Colors.cyan),
          title: const Text('توزيع على مندوب', style: TextStyle(color: AppColors.text)),
          onTap: () { Navigator.pop(ctx); _showAssignDialog(lead); },
        ),
        ListTile(
          leading: const Icon(Icons.swap_horiz, color: Colors.orange),
          title: const Text('تغيير المرحلة', style: TextStyle(color: AppColors.text)),
          onTap: () { Navigator.pop(ctx); _showStageDialog(lead); },
        ),
        ListTile(
          leading: const Icon(Icons.delete, color: Colors.red),
          title: const Text('حذف الليد', style: TextStyle(color: Colors.red)),
          onTap: () { Navigator.pop(ctx); _deleteLead(lead); },
        ),
        const SizedBox(height: 8),
      ])),
    );
  }

  void _showAssignDialog(dynamic lead) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppThemeDecorations.cardColor(context),
        title: const Text('توزيع على مندوب', style: TextStyle(color: AppColors.text, fontSize: 16)),
        content: SizedBox(
          width: 300,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.person_off, color: AppColors.muted),
              title: const Text('إلغاء التوزيع', style: TextStyle(color: AppColors.text, fontSize: 13)),
              onTap: () async {
                Navigator.pop(ctx);
                await _assignLeadTo(lead['id'], null);
              },
            ),
            const Divider(color: AppColors.border),
            ..._staff.map((s) => ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withOpacity(0.15),
                radius: 16,
                child: Text((s['name'] ?? 'م')[0], style: const TextStyle(color: AppColors.primary, fontSize: 12)),
              ),
              title: Text(s['name'] ?? '', style: const TextStyle(color: AppColors.text, fontSize: 13)),
              subtitle: Text(s['role'] ?? '', style: const TextStyle(color: AppColors.muted, fontSize: 10)),
              trailing: lead['assignedTo'] == s['id'] ? const Icon(Icons.check_circle, color: AppColors.primary, size: 18) : null,
              onTap: () async {
                Navigator.pop(ctx);
                await _assignLeadTo(lead['id'], s['id']);
              },
            )),
          ]),
        ),
      ),
    );
  }

  Future<void> _assignLeadTo(int leadId, int? staffId) async {
    try {
      await ApiService.mutate('crm.assignLead', input: {'id': leadId, 'assignedTo': staffId});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم التوزيع بنجاح'), backgroundColor: Colors.green));
      _loadAll();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التوزيع: $e'), backgroundColor: Colors.red));
    }
  }

  void _showStageDialog(dynamic lead) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppThemeDecorations.cardColor(context),
        title: const Text('تغيير المرحلة', style: TextStyle(color: AppColors.text, fontSize: 16)),
        children: _stages.map((s) => SimpleDialogOption(
          onPressed: () async {
            Navigator.pop(ctx);
            try {
              await ApiService.mutate('crm.updateStage', input: {'id': lead['id'], 'stage': s['key']});
              _loadAll();
            } catch (e) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e'), backgroundColor: Colors.red));
            }
          },
          child: Row(children: [
            Icon(s['icon'] as IconData, color: s['color'] as Color, size: 20),
            const SizedBox(width: 10),
            Text(s['label'] as String, style: TextStyle(color: lead['pipelineStage'] == s['key'] ? AppColors.primary : AppColors.text, fontWeight: lead['pipelineStage'] == s['key'] ? FontWeight.bold : FontWeight.normal)),
            if (lead['pipelineStage'] == s['key']) ...[const Spacer(), const Icon(Icons.check, color: AppColors.primary, size: 18)],
          ]),
        )).toList(),
      ),
    );
  }

  Future<void> _deleteLead(dynamic lead) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppThemeDecorations.cardColor(context),
        title: const Text('حذف الليد', style: TextStyle(color: Colors.red)),
        content: Text('هل تريد حذف "${lead['name']}"؟', style: const TextStyle(color: AppColors.text)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء', style: TextStyle(color: AppColors.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await ApiService.mutate('crm.deleteLead', input: {'id': lead['id']});
        _loadAll();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحذف: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _showCreateLead() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String priority = 'medium';
    int? assignedTo;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        backgroundColor: AppThemeDecorations.cardColor(context),
        title: const Text('إضافة ليد جديد', style: TextStyle(color: AppColors.text, fontSize: 16)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          _inputField(nameCtrl, 'الاسم *', Icons.person),
          const SizedBox(height: 10),
          _inputField(phoneCtrl, 'رقم الهاتف', Icons.phone),
          const SizedBox(height: 10),
          _inputField(emailCtrl, 'البريد الإلكتروني', Icons.email),
          const SizedBox(height: 10),
          _inputField(notesCtrl, 'ملاحظات', Icons.note, maxLines: 2),
          const SizedBox(height: 12),
          Row(children: [
            const Text('الأولوية: ', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(width: 8),
            ...['low', 'medium', 'high'].map((p) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setD(() => priority = p),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: priority == p ? (_priorityColors[p] ?? Colors.grey).withOpacity(0.2) : AppThemeDecorations.pageBackground(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: priority == p ? (_priorityColors[p] ?? Colors.grey) : AppColors.border),
                  ),
                  child: Text(_priorityLabels[p] ?? '', style: TextStyle(color: priority == p ? _priorityColors[p] : AppColors.muted, fontSize: 11)),
                ),
              ),
            )),
          ]),
          if (_staff.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              value: assignedTo,
              decoration: InputDecoration(
                labelText: 'توزيع على',
                labelStyle: const TextStyle(color: AppColors.muted, fontSize: 12),
                filled: true, fillColor: AppThemeDecorations.pageBackground(context),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              dropdownColor: AppThemeDecorations.cardColor(context),
              style: const TextStyle(color: AppColors.text, fontSize: 13),
              items: [
                const DropdownMenuItem(value: null, child: Text('بدون توزيع')),
                ..._staff.map((s) => DropdownMenuItem(value: s['id'] as int, child: Text(s['name'] ?? ''))),
              ],
              onChanged: (v) => setD(() => assignedTo = v),
            ),
          ],
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء', style: TextStyle(color: AppColors.muted))),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              try {
                await ApiService.mutate('crm.createLead', input: {
                  'name': nameCtrl.text.trim(),
                  'phone': phoneCtrl.text.trim(),
                  'email': emailCtrl.text.trim(),
                  'notes': notesCtrl.text.trim(),
                  'priority': priority,
                  if (assignedTo != null) 'assignedTo': assignedTo,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                _loadAll();
              } catch (e) {
                if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e'), backgroundColor: Colors.red));
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      )),
    );
  }

  Widget _inputField(TextEditingController ctrl, String hint, IconData icon, {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.text, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint, hintStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
        prefixIcon: Icon(icon, color: AppColors.muted, size: 18),
        filled: true, fillColor: AppThemeDecorations.pageBackground(context),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  String _formatDate(dynamic d) {
    if (d == null) return '';
    try {
      final dt = DateTime.parse(d.toString());
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return '';
    }
  }
}
