import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';

class AdminAccountingScreen extends StatefulWidget {
  const AdminAccountingScreen({super.key});
  @override
  State<AdminAccountingScreen> createState() => _AdminAccountingScreenState();
}

class _AdminAccountingScreenState extends State<AdminAccountingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _loading = true;

  Map<String, dynamic> _dashboard = {};
  List<Map<String, dynamic>> _balances = [];
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _pendingApprovals = [];
  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _expenseCategories = [];

  String? _filterTechId;
  String? _filterType;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.query('acc.getDashboard', input: {}),
        ApiService.query('acc.getCustodyBalances', input: {}),
        ApiService.query('acc.getTransactions', input: {'limit': 100}),
        ApiService.query('acc.getTransactions', input: {'status': 'pending', 'type': 'expense'}),
        ApiService.query('clients.staff'),
        ApiService.query('acc.getExpenseCategories'),
      ]);
      setState(() {
        _dashboard = Map<String, dynamic>.from(results[0]['data'] ?? {});
        _balances = (results[1]['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
        _transactions = (results[2]['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
        _pendingApprovals = (results[3]['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
        _staff = (results[4]['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
        _expenseCategories = (results[5]['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  // ── Type helpers ─────────────────────────────────────────────

  static const _typeLabels = {
    'collection': 'تحصيل',
    'expense': 'مصروف',
    'advance': 'سلفة',
    'settlement': 'تسليم عهدة',
    'adjustment': 'تسوية',
  };

  static const _typeIcons = {
    'collection': Icons.arrow_downward,
    'expense': Icons.arrow_upward,
    'advance': Icons.account_balance_wallet,
    'settlement': Icons.handshake,
    'adjustment': Icons.swap_vert,
  };

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

  Color _statusColor(String status) {
    switch (status) {
      case 'approved': return Colors.green;
      case 'pending': return Colors.orange;
      case 'rejected': return Colors.red;
      default: return AppColors.muted;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved': return 'معتمد';
      case 'pending': return 'في انتظار الاعتماد';
      case 'rejected': return 'مرفوض';
      default: return status;
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

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeDecorations.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppThemeDecorations.cardColor(context),
        title: const Text('الحسابات والعهد', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: AppColors.muted), onPressed: _loadAll),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.muted,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          tabs: [
            Tab(text: 'لوحة التحكم', icon: Icon(Icons.dashboard_outlined, size: 18)),
            Tab(
              icon: Badge(
                isLabelVisible: _pendingApprovals.isNotEmpty,
                label: Text('${_pendingApprovals.length}', style: const TextStyle(fontSize: 9)),
                child: const Icon(Icons.approval, size: 18),
              ),
              text: 'الاعتمادات',
            ),
            Tab(text: 'العهد', icon: Icon(Icons.account_balance_wallet_outlined, size: 18)),
            Tab(text: 'الحركات', icon: Icon(Icons.receipt_long_outlined, size: 18)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateTransaction,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('حركة جديدة', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildDashboardTab(),
                _buildApprovalsTab(),
                _buildCustodyTab(),
                _buildTransactionsTab(),
              ],
            ),
    );
  }

  // ── Tab 1: Dashboard ─────────────────────────────────────────

  Widget _buildDashboardTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Total custody banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primary.withOpacity(0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: [
              const Text('إجمالي العهد الحالية', style: TextStyle(color: Colors.black54, fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                _formatAmount(_dashboard['totalCustody'] ?? 0),
                style: const TextStyle(color: Colors.black, fontSize: 32, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                'الفترة: ${_formatDate(_dashboard['dateFrom']?.toString())} – ${_formatDate(_dashboard['dateTo']?.toString())}',
                style: const TextStyle(color: Colors.black54, fontSize: 11),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // Stats grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: [
              _dashCard('التحصيلات', _dashboard['totalCollections'] ?? 0, Icons.arrow_downward, Colors.green),
              _dashCard('المصروفات', _dashboard['totalExpenses'] ?? 0, Icons.arrow_upward, Colors.red),
              _dashCard('السلف', _dashboard['totalAdvances'] ?? 0, Icons.account_balance_wallet, Colors.blue),
              _dashCard('التسليمات', _dashboard['totalSettlements'] ?? 0, Icons.handshake, Colors.orange),
            ],
          ),
          const SizedBox(height: 16),

          // Pending approvals alert
          if ((_dashboard['pendingCount'] ?? 0) > 0)
            GestureDetector(
              onTap: () => _tabCtrl.animateTo(1),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_dashboard['pendingCount']} مصروفات في انتظار الاعتماد',
                        style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('بقيمة ${_formatAmount(_dashboard['pendingExpenses'] ?? 0)}',
                        style: const TextStyle(color: Colors.orange, fontSize: 12)),
                  ])),
                  const Icon(Icons.arrow_forward_ios, color: Colors.orange, size: 14),
                ]),
              ),
            ),
          const SizedBox(height: 16),

          // Top custody holders
          _sectionTitle('أعلى العهد'),
          ..._balances.where((b) => (b['balance'] as num? ?? 0) > 0).take(5).map((b) {
            final balance = (b['balance'] as num? ?? 0).toDouble();
            final maxBalance = _balances.isEmpty ? 1.0 : _balances.map((b) => (b['balance'] as num? ?? 0).abs()).reduce((a, b) => a > b ? a : b).toDouble();
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppThemeDecorations.cardColor(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(children: [
                Row(children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.primary.withOpacity(0.2),
                    child: Text((b['technicianName'] ?? '?').toString()[0],
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(b['technicianName'] ?? '—',
                      style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold))),
                  Text(_formatAmount(balance),
                      style: TextStyle(
                        color: balance > 0 ? Colors.orange : Colors.green,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      )),
                ]),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: maxBalance > 0 ? balance.abs() / maxBalance : 0,
                    backgroundColor: AppColors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(balance > 0 ? Colors.orange : Colors.green),
                    minHeight: 4,
                  ),
                ),
              ]),
            );
          }),
        ],
      ),
    );
  }

  Widget _dashCard(String title, dynamic amount, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeDecorations.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 16),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_formatAmount(amount),
              style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900)),
          Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        ]),
      ]),
    );
  }

  // ── Tab 2: Approvals ─────────────────────────────────────────

  Widget _buildApprovalsTab() {
    if (_pendingApprovals.isEmpty) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 64, color: Colors.green.withOpacity(0.4)),
          const SizedBox(height: 16),
          const Text('لا توجد مصروفات في انتظار الاعتماد', style: TextStyle(color: AppColors.muted, fontSize: 16)),
        ],
      ));
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _pendingApprovals.length,
        itemBuilder: (_, i) {
          final tx = _pendingApprovals[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppThemeDecorations.cardColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.4)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: Colors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.receipt_long, color: Colors.orange, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tx['technicianName'] ?? '—', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
                  Text(tx['description'] ?? '', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ])),
                Text(_formatAmount(tx['amount']),
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w900, fontSize: 18)),
              ]),
              if (tx['category'] != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppThemeDecorations.pageBackground(context), borderRadius: BorderRadius.circular(8)),
                  child: Text('📂 ${tx['category']}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ),
              ],
              if (tx['taskTitle'] != null) ...[
                const SizedBox(height: 4),
                Text('📋 ${tx['taskTitle']}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              ],
              const SizedBox(height: 4),
              Text('📅 ${_formatDate(tx['createdAt']?.toString())}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _approveTransaction(tx['id'], 'approve'),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('اعتماد', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showRejectDialog(tx['id']),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('رفض', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ]),
            ]),
          );
        },
      ),
    );
  }

  // ── Tab 3: Custody Balances ──────────────────────────────────

  Widget _buildCustodyTab() {
    final sorted = List<Map<String, dynamic>>.from(_balances)
      ..sort((a, b) => ((b['balance'] as num?) ?? 0).compareTo((a['balance'] as num?) ?? 0));

    return RefreshIndicator(
      onRefresh: _loadAll,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sorted.length,
        itemBuilder: (_, i) {
          final b = sorted[i];
          final balance = (b['balance'] as num? ?? 0).toDouble();
          final totalIn = (b['totalIn'] as num? ?? 0).toDouble();
          final totalOut = (b['totalOut'] as num? ?? 0).toDouble();
          final pending = (b['pendingExpenses'] as num? ?? 0).toDouble();

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppThemeDecorations.cardColor(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: balance > 0 ? Colors.orange.withOpacity(0.3) : Colors.green.withOpacity(0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.primary.withOpacity(0.2),
                  child: Text((b['technicianName'] ?? '?').toString()[0],
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 18)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b['technicianName'] ?? '—', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16)),
                  Text('${b['transactionCount'] ?? 0} حركة', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Text('رصيد العهدة', style: TextStyle(color: AppColors.muted, fontSize: 10)),
                  Text(
                    _formatAmount(balance),
                    style: TextStyle(
                      color: balance > 0 ? Colors.orange : (balance < 0 ? Colors.red : Colors.green),
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                ]),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                _miniStat('وارد', totalIn, Colors.green),
                const SizedBox(width: 12),
                _miniStat('صادر', totalOut, Colors.red),
                const SizedBox(width: 12),
                _miniStat('معلق', pending, Colors.orange),
              ]),
              if (balance > 0) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showSettleDialog(b),
                    icon: const Icon(Icons.handshake, size: 16),
                    label: const Text('تصفية العهدة', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ]),
          );
        },
      ),
    );
  }

  Widget _miniStat(String label, double value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(children: [
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
          Text(_formatAmount(value), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900)),
        ]),
      ),
    );
  }

  // ── Tab 4: Transactions ──────────────────────────────────────

  Widget _buildTransactionsTab() {
    var filtered = List<Map<String, dynamic>>.from(_transactions);
    if (_filterTechId != null) {
      filtered = filtered.where((t) => t['technicianId'].toString() == _filterTechId).toList();
    }
    if (_filterType != null) {
      filtered = filtered.where((t) => t['type'] == _filterType).toList();
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      color: AppColors.primary,
      child: Column(children: [
        // Filters
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              _filterChip('الكل', _filterType == null && _filterTechId == null, () {
                setState(() { _filterType = null; _filterTechId = null; });
              }),
              ..._typeLabels.entries.map((e) => _filterChip(
                e.value,
                _filterType == e.key,
                () => setState(() => _filterType = _filterType == e.key ? null : e.key),
                color: _typeColor(e.key),
              )),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('لا توجد حركات', style: TextStyle(color: AppColors.muted)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final tx = filtered[i];
                    final type = tx['type'] ?? '';
                    final isIncome = type == 'collection' || type == 'advance';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppThemeDecorations.cardColor(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: _typeColor(type).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(_typeIcons[type] ?? Icons.receipt, color: _typeColor(type), size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Text(_typeLabels[type] ?? type,
                                style: TextStyle(color: _typeColor(type), fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: _statusColor(tx['status'] ?? '').withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(_statusLabel(tx['status'] ?? ''),
                                  style: TextStyle(color: _statusColor(tx['status'] ?? ''), fontSize: 9, fontWeight: FontWeight.bold)),
                            ),
                          ]),
                          const SizedBox(height: 2),
                          Text(tx['technicianName'] ?? '—',
                              style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w500, fontSize: 13)),
                          if ((tx['description'] ?? '').toString().isNotEmpty)
                            Text(tx['description'], style: const TextStyle(color: AppColors.muted, fontSize: 11),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(_formatDate(tx['createdAt']?.toString()),
                              style: const TextStyle(color: AppColors.muted, fontSize: 10)),
                        ])),
                        Text(
                          '${isIncome ? '+' : '-'}${_formatAmount(tx['amount'])}',
                          style: TextStyle(
                            color: isIncome ? Colors.green : Colors.red,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap, {Color? color}) {
    final c = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c.withOpacity(0.15) : AppThemeDecorations.cardColor(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? c : AppColors.border),
        ),
        child: Text(label, style: TextStyle(
          color: selected ? c : AppColors.muted,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        )),
      ),
    );
  }

  // ── Dialogs ──────────────────────────────────────────────────

  void _showCreateTransaction() {
    String selectedType = 'collection';
    int? selectedTechId;
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String? selectedCategory;

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
                const Text('حركة مالية جديدة', style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),

                const Text('نوع الحركة', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: _typeLabels.entries.map((e) {
                  final sel = selectedType == e.key;
                  return GestureDetector(
                    onTap: () => setS(() => selectedType = e.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? _typeColor(e.key).withOpacity(0.15) : AppThemeDecorations.pageBackground(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: sel ? _typeColor(e.key) : AppColors.border),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_typeIcons[e.key], size: 16, color: sel ? _typeColor(e.key) : AppColors.muted),
                        const SizedBox(width: 6),
                        Text(e.value, style: TextStyle(
                            color: sel ? _typeColor(e.key) : AppColors.muted,
                            fontWeight: sel ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
                      ]),
                    ),
                  );
                }).toList()),
                const SizedBox(height: 16),

                const Text('الفني', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: selectedTechId,
                  dropdownColor: AppThemeDecorations.cardColor(context),
                  style: const TextStyle(color: AppColors.text),
                  decoration: _inputDec(hint: 'اختر الفني'),
                  items: _staff.map((s) => DropdownMenuItem(
                    value: s['id'] is int ? s['id'] as int : int.tryParse(s['id'].toString()),
                    child: Text(s['name'] ?? '', style: const TextStyle(color: AppColors.text)),
                  )).toList(),
                  onChanged: (v) => setS(() => selectedTechId = v),
                ),
                const SizedBox(height: 16),

                const Text('المبلغ (ج.م)', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.bold),
                  decoration: _inputDec(hint: '0.00'),
                ),
                const SizedBox(height: 16),

                if (selectedType == 'expense') ...[
                  const Text('تصنيف المصروف', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: _expenseCategories.map((c) {
                    final sel = selectedCategory == c['name'];
                    return GestureDetector(
                      onTap: () => setS(() => selectedCategory = c['name']),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: sel ? AppColors.primary.withOpacity(0.15) : AppThemeDecorations.pageBackground(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: sel ? AppColors.primary : AppColors.border),
                        ),
                        child: Text(c['name'], style: TextStyle(
                            color: sel ? AppColors.primary : AppColors.muted, fontSize: 12,
                            fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                      ),
                    );
                  }).toList()),
                  const SizedBox(height: 16),
                ],

                const Text('الوصف', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  style: const TextStyle(color: AppColors.text),
                  decoration: _inputDec(hint: 'وصف الحركة...'),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (selectedTechId == null || amountCtrl.text.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('اختر الفني وأدخل المبلغ'), backgroundColor: Colors.red));
                        return;
                      }
                      Navigator.pop(ctx);
                      try {
                        await ApiService.mutate('acc.createTransaction', input: {
                          'type': selectedType,
                          'technicianId': selectedTechId,
                          'amount': double.tryParse(amountCtrl.text) ?? 0,
                          'description': descCtrl.text.trim(),
                          'category': selectedCategory,
                        });
                        _loadAll();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تم إضافة الحركة بنجاح'), backgroundColor: Colors.green));
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('إضافة الحركة', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  ),
                ),
              ],
            )),
          ),
        ),
      ),
    );
  }

  Future<void> _approveTransaction(int id, String action) async {
    try {
      await ApiService.mutate('acc.approveTransaction', input: {'id': id, 'action': action});
      _loadAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(action == 'approve' ? 'تم اعتماد المصروف' : 'تم رفض المصروف'),
          backgroundColor: action == 'approve' ? Colors.green : Colors.red,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _showRejectDialog(int id) {
    final noteCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppThemeDecorations.cardColor(context),
          title: const Text('رفض المصروف', style: TextStyle(color: AppColors.text)),
          content: TextField(
            controller: noteCtrl,
            maxLines: 2,
            style: const TextStyle(color: AppColors.text),
            decoration: _inputDec(hint: 'سبب الرفض (اختياري)'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء', style: TextStyle(color: AppColors.muted)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await ApiService.mutate('acc.approveTransaction', input: {
                    'id': id,
                    'action': 'reject',
                    'note': noteCtrl.text.trim(),
                  });
                  _loadAll();
                } catch (_) {}
              },
              child: const Text('رفض', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettleDialog(Map<String, dynamic> b) {
    final amountCtrl = TextEditingController(text: (b['balance'] ?? 0).toString());
    final descCtrl = TextEditingController(text: 'تصفية عهدة');

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppThemeDecorations.cardColor(context),
          title: Text('تصفية عهدة ${b['technicianName']}', style: const TextStyle(color: AppColors.text, fontSize: 16)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('الرصيد الحالي: ${_formatAmount(b['balance'])}',
                style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.text),
              decoration: _inputDec(hint: 'المبلغ المسلّم'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              style: const TextStyle(color: AppColors.text),
              decoration: _inputDec(hint: 'ملاحظات'),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء', style: TextStyle(color: AppColors.muted)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await ApiService.mutate('acc.settleCustody', input: {
                    'technicianId': b['technicianId'],
                    'amount': double.tryParse(amountCtrl.text) ?? 0,
                    'description': descCtrl.text.trim(),
                  });
                  _loadAll();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم تصفية العهدة بنجاح'), backgroundColor: Colors.green));
                  }
                } catch (_) {}
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('تأكيد التصفية', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────

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

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(title, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16)),
    );
  }
}
