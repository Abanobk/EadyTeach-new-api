import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';
import '../../services/api_service.dart';

class AdminPermissionsScreen extends StatefulWidget {
  const AdminPermissionsScreen({super.key});
  @override
  State<AdminPermissionsScreen> createState() => _AdminPermissionsScreenState();
}

class _AdminPermissionsScreenState extends State<AdminPermissionsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _loading = true;
  List<Map<String, dynamic>> _roles = [];
  List<Map<String, dynamic>> _users = [];
  Map<String, dynamic> _permModules = {};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.query('permissions.getRoles', input: {}),
        ApiService.query('permissions.getUsers', input: {}),
        ApiService.query('permissions.getAllPermissions', input: {}),
      ]);
      setState(() {
        _roles = (results[0]['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
        _users = (results[1]['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
        _permModules = Map<String, dynamic>.from(results[2]['data'] ?? {});
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل البيانات: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return AppColors.muted;
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return AppColors.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppThemeDecorations.pageBackground(context),
        appBar: AppBar(
          backgroundColor: AppThemeDecorations.cardColor(context),
          title: const Text('إدارة الصلاحيات', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
          iconTheme: const IconThemeData(color: AppColors.text),
          actions: [
            IconButton(icon: const Icon(Icons.refresh, color: AppColors.muted), onPressed: _loadData),
          ],
          bottom: TabBar(
            controller: _tabCtrl,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.muted,
            tabs: [
              Tab(icon: const Icon(Icons.groups, size: 20), child: const Text('الأدوار', style: TextStyle(fontSize: 12))),
              Tab(icon: const Icon(Icons.security, size: 20), child: const Text('الصلاحيات', style: TextStyle(fontSize: 12))),
              Tab(icon: const Icon(Icons.person_search, size: 20), child: const Text('المستخدمون', style: TextStyle(fontSize: 12))),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildRolesTab(),
                  _buildPermissionsTab(),
                  _buildUsersTab(),
                ],
              ),
      ),
    );
  }

  // ─── Roles Tab ──────────────────────────────────────────────
  Widget _buildRolesTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Add role button
          GestureDetector(
            onTap: _showCreateRoleDialog,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withOpacity(0.3), style: BorderStyle.solid),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline, color: AppColors.primary, size: 22),
                  SizedBox(width: 8),
                  Text('إضافة دور جديد', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ..._roles.map((role) => _buildRoleCard(role)),
        ],
      ),
    );
  }

  Widget _buildRoleCard(Map<String, dynamic> role) {
    final color = _parseColor(role['color']);
    final isSystem = role['isSystem'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeDecorations.cardColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.shield_outlined, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(role['nameAr'] ?? '', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(width: 8),
                        if (isSystem)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('أساسي', style: TextStyle(color: AppColors.muted, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    Text(role['slug'] ?? '', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  ],
                ),
              ),
              if (!isSystem)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: AppColors.muted, size: 20),
                  color: AppThemeDecorations.cardColor(context),
                  onSelected: (action) {
                    if (action == 'edit') _showEditRoleDialog(role);
                    if (action == 'delete') _confirmDeleteRole(role);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Row(children: [
                      Icon(Icons.edit, size: 16, color: AppColors.muted),
                      SizedBox(width: 8),
                      Text('تعديل', style: TextStyle(color: AppColors.text)),
                    ])),
                    const PopupMenuItem(value: 'delete', child: Row(children: [
                      Icon(Icons.delete_outline, size: 16, color: Colors.red),
                      SizedBox(width: 8),
                      Text('حذف', style: TextStyle(color: Colors.red)),
                    ])),
                  ],
                ),
            ],
          ),
          if (role['description'] != null && role['description'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(role['description'], style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _roleStatChip(Icons.security, '${role['permCount'] ?? 0} صلاحية', color),
              const SizedBox(width: 10),
              _roleStatChip(Icons.person, '${role['userCount'] ?? 0} مستخدم', Colors.blue),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  _tabCtrl.animateTo(1);
                  Future.delayed(const Duration(milliseconds: 300), () {
                    if (mounted) setState(() => _selectedRoleForPerms = role['id']);
                  });
                },
                icon: Icon(Icons.tune, size: 16, color: color),
                label: Text('إدارة الصلاحيات', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roleStatChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ─── Permissions Tab ────────────────────────────────────────
  int? _selectedRoleForPerms;
  Set<String> _rolePerms = {};
  bool _loadingPerms = false;

  Widget _buildPermissionsTab() {
    final roleOptions = _roles.where((r) => r['slug'] != 'user').toList();

    return Column(
      children: [
        // Role selector
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppThemeDecorations.cardColor(context),
            border: const Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('اختر الدور لتعديل صلاحياته:', style: TextStyle(color: AppColors.muted, fontSize: 12)),
              const SizedBox(height: 8),
              SizedBox(
                height: 42,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: roleOptions.map((role) {
                    final selected = _selectedRoleForPerms == role['id'];
                    final color = _parseColor(role['color']);
                    final isAdmin = role['slug'] == 'admin';
                    return GestureDetector(
                      onTap: () => _selectRoleForPerms(role['id']),
                      child: Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected ? color.withOpacity(0.15) : AppThemeDecorations.pageBackground(context),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: selected ? color : AppColors.border),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (isAdmin) ...[
                            Icon(Icons.lock, size: 14, color: selected ? color : AppColors.muted),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            role['nameAr'] ?? '',
                            style: TextStyle(
                              color: selected ? color : AppColors.muted,
                              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        // Permissions list
        Expanded(
          child: _selectedRoleForPerms == null
              ? const Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.touch_app, size: 64, color: AppColors.muted),
                    SizedBox(height: 16),
                    Text('اختر دور من الأعلى لعرض صلاحياته', style: TextStyle(color: AppColors.muted, fontSize: 14)),
                  ]),
                )
              : _loadingPerms
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _buildPermissionsList(),
        ),
      ],
    );
  }

  Future<void> _selectRoleForPerms(int roleId) async {
    setState(() {
      _selectedRoleForPerms = roleId;
      _loadingPerms = true;
    });
    try {
      final res = await ApiService.query('permissions.getRolePermissions', input: {'roleId': roleId});
      final perms = (res['data'] as List? ?? []).map((e) => e.toString()).toSet();
      setState(() {
        _rolePerms = perms;
        _loadingPerms = false;
      });
    } catch (e) {
      setState(() => _loadingPerms = false);
    }
  }

  Widget _buildPermissionsList() {
    final selectedRole = _roles.firstWhere((r) => r['id'] == _selectedRoleForPerms, orElse: () => {});
    final isAdmin = selectedRole['slug'] == 'admin';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (isAdmin)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, color: Colors.red, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('المسؤول لديه كل الصلاحيات تلقائياً ولا يمكن تعديلها',
                  style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600))),
            ]),
          ),
        ..._permModules.entries.map((entry) {
          final moduleKey = entry.key;
          final module = Map<String, dynamic>.from(entry.value);
          final actions = Map<String, dynamic>.from(module['actions'] ?? {});
          final moduleLabel = module['label'] ?? moduleKey;

          final allKeys = actions.keys.map((a) => '$moduleKey.$a').toList();
          final allChecked = allKeys.every((k) => _rolePerms.contains(k));
          final someChecked = allKeys.any((k) => _rolePerms.contains(k));

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppThemeDecorations.cardColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: someChecked ? AppColors.primary.withOpacity(0.3) : AppColors.border),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: (someChecked ? AppColors.primary : AppColors.muted).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.folder_outlined, color: someChecked ? AppColors.primary : AppColors.muted, size: 18),
                ),
                title: Row(
                  children: [
                    Expanded(child: Text(moduleLabel, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14))),
                    if (!isAdmin)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            if (allChecked) {
                              _rolePerms.removeAll(allKeys);
                            } else {
                              _rolePerms.addAll(allKeys);
                            }
                          });
                          _savePermissions();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (allChecked ? AppColors.primary : AppColors.muted).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            allChecked ? 'إلغاء الكل' : 'تفعيل الكل',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: allChecked ? AppColors.primary : AppColors.muted),
                          ),
                        ),
                      ),
                  ],
                ),
                children: actions.entries.map((actionEntry) {
                  final permKey = '$moduleKey.${actionEntry.key}';
                  final actionLabel = actionEntry.value.toString();
                  final enabled = isAdmin || _rolePerms.contains(permKey);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        const SizedBox(width: 48),
                        Expanded(child: Text(actionLabel, style: TextStyle(color: enabled ? AppColors.text : AppColors.muted, fontSize: 13))),
                        Switch(
                          value: enabled,
                          onChanged: isAdmin ? null : (val) {
                            setState(() {
                              if (val) {
                                _rolePerms.add(permKey);
                              } else {
                                _rolePerms.remove(permKey);
                              }
                            });
                            _savePermissions();
                          },
                          activeColor: AppColors.primary,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          );
        }),
      ],
    );
  }

  Future<void> _savePermissions() async {
    if (_selectedRoleForPerms == null) return;
    try {
      await ApiService.mutate('permissions.updateRolePermissions', input: {
        'roleId': _selectedRoleForPerms,
        'permissions': _rolePerms.toList(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── Users Tab ──────────────────────────────────────────────
  String? _usersFilterRole;

  Widget _buildUsersTab() {
    final filteredUsers = _usersFilterRole != null
        ? _users.where((u) => u['role'] == _usersFilterRole).toList()
        : _users;

    return Column(
      children: [
        // Filter chips
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppThemeDecorations.cardColor(context),
            border: const Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _userFilterChip(null, 'الكل', Icons.people, null),
                ..._roles.map((role) =>
                  _userFilterChip(role['slug'], role['nameAr'] ?? '', Icons.person, _parseColor(role['color'])),
                ),
              ],
            ),
          ),
        ),
        // Users list
        Expanded(
          child: filteredUsers.isEmpty
              ? const Center(child: Text('لا يوجد مستخدمون', style: TextStyle(color: AppColors.muted)))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  color: AppColors.primary,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredUsers.length,
                    itemBuilder: (_, i) => _buildUserCard(filteredUsers[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _userFilterChip(String? roleSlug, String label, IconData icon, Color? color) {
    final selected = _usersFilterRole == roleSlug;
    final chipColor = color ?? AppColors.primary;
    return GestureDetector(
      onTap: () => setState(() => _usersFilterRole = roleSlug),
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? chipColor.withOpacity(0.15) : AppThemeDecorations.pageBackground(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? chipColor : AppColors.border),
        ),
        child: Text(label, style: TextStyle(
          color: selected ? chipColor : AppColors.muted,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        )),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final roleColor = _parseColor(user['roleColor']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeDecorations.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: roleColor.withOpacity(0.15),
            radius: 22,
            child: Text(
              (user['name'] ?? 'U')[0].toUpperCase(),
              style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user['name'] ?? '', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14)),
                Text(user['email'] ?? '', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                if (user['phone'] != null && user['phone'].toString().isNotEmpty)
                  Text(user['phone'], style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _showChangeRoleDialog(user),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: roleColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: roleColor.withOpacity(0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(user['roleNameAr'] ?? user['role'] ?? '', style: TextStyle(color: roleColor, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(width: 4),
                Icon(Icons.edit, size: 12, color: roleColor),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Dialogs ────────────────────────────────────────────────

  void _showCreateRoleDialog() {
    final nameArCtrl = TextEditingController();
    final slugCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String selectedColor = '#607D8B';

    final colors = ['#F44336', '#E91E63', '#9C27B0', '#673AB7', '#3F51B5', '#2196F3', '#03A9F4', '#009688', '#4CAF50', '#FF9800', '#FF5722', '#795548', '#607D8B'];

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            backgroundColor: AppThemeDecorations.cardColor(context),
            title: const Text('إضافة دور جديد', style: TextStyle(color: AppColors.text, fontSize: 18)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('اسم الدور بالعربي *', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameArCtrl,
                    style: const TextStyle(color: AppColors.text),
                    decoration: _inputDec(hint: 'مثال: محاسب'),
                    onChanged: (v) {
                      if (slugCtrl.text.isEmpty || slugCtrl.text == _toSlug(nameArCtrl.text)) {
                        slugCtrl.text = _toSlug(v);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('المعرف (بالإنجليزي) *', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: slugCtrl,
                    style: const TextStyle(color: AppColors.text),
                    decoration: _inputDec(hint: 'مثال: accountant'),
                  ),
                  const SizedBox(height: 12),
                  const Text('الوصف', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    style: const TextStyle(color: AppColors.text),
                    decoration: _inputDec(hint: 'وصف مختصر للدور'),
                  ),
                  const SizedBox(height: 12),
                  const Text('اللون', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: colors.map((c) => GestureDetector(
                      onTap: () => setS(() => selectedColor = c),
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: _parseColor(c),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selectedColor == c ? Colors.white : Colors.transparent,
                            width: 2,
                          ),
                          boxShadow: selectedColor == c ? [BoxShadow(color: _parseColor(c).withOpacity(0.5), blurRadius: 6)] : null,
                        ),
                      ),
                    )).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء', style: TextStyle(color: AppColors.muted)),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameArCtrl.text.isEmpty || slugCtrl.text.isEmpty) return;
                  Navigator.pop(ctx);
                  try {
                    await ApiService.mutate('permissions.createRole', input: {
                      'slug': slugCtrl.text.trim(),
                      'name': slugCtrl.text.trim(),
                      'nameAr': nameArCtrl.text.trim(),
                      'description': descCtrl.text.trim(),
                      'color': selectedColor,
                    });
                    _loadData();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم إنشاء الدور بنجاح'), backgroundColor: Colors.green),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                child: const Text('إنشاء', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditRoleDialog(Map<String, dynamic> role) {
    final nameArCtrl = TextEditingController(text: role['nameAr'] ?? '');
    final descCtrl = TextEditingController(text: role['description'] ?? '');
    String selectedColor = role['color'] ?? '#607D8B';

    final colors = ['#F44336', '#E91E63', '#9C27B0', '#673AB7', '#3F51B5', '#2196F3', '#03A9F4', '#009688', '#4CAF50', '#FF9800', '#FF5722', '#795548', '#607D8B'];

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            backgroundColor: AppThemeDecorations.cardColor(context),
            title: Text('تعديل: ${role['nameAr']}', style: const TextStyle(color: AppColors.text, fontSize: 18)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('اسم الدور', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(controller: nameArCtrl, style: const TextStyle(color: AppColors.text), decoration: _inputDec()),
                  const SizedBox(height: 12),
                  const Text('الوصف', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(controller: descCtrl, maxLines: 2, style: const TextStyle(color: AppColors.text), decoration: _inputDec()),
                  const SizedBox(height: 12),
                  const Text('اللون', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: colors.map((c) => GestureDetector(
                      onTap: () => setS(() => selectedColor = c),
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: _parseColor(c),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: selectedColor == c ? Colors.white : Colors.transparent, width: 2),
                          boxShadow: selectedColor == c ? [BoxShadow(color: _parseColor(c).withOpacity(0.5), blurRadius: 6)] : null,
                        ),
                      ),
                    )).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء', style: TextStyle(color: AppColors.muted))),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    await ApiService.mutate('permissions.updateRole', input: {
                      'id': role['id'],
                      'nameAr': nameArCtrl.text.trim(),
                      'description': descCtrl.text.trim(),
                      'color': selectedColor,
                    });
                    _loadData();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                child: const Text('حفظ', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteRole(Map<String, dynamic> role) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppThemeDecorations.cardColor(context),
          title: const Text('حذف الدور', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          content: Text('هل أنت متأكد من حذف "${role['nameAr']}"؟', style: const TextStyle(color: AppColors.text)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء', style: TextStyle(color: AppColors.muted))),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await ApiService.mutate('permissions.deleteRole', input: {'id': role['id']});
                  _loadData();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('حذف', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangeRoleDialog(Map<String, dynamic> user) {
    String? selectedRole = user['role'];

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            backgroundColor: AppThemeDecorations.cardColor(context),
            title: Text('تغيير دور: ${user['name']}', style: const TextStyle(color: AppColors.text, fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: _roles.map((role) {
                final isSelected = selectedRole == role['slug'];
                final color = _parseColor(role['color']);
                return GestureDetector(
                  onTap: () => setS(() => selectedRole = role['slug']),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected ? color.withOpacity(0.12) : AppThemeDecorations.pageBackground(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isSelected ? color : AppColors.border),
                    ),
                    child: Row(children: [
                      Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: isSelected ? color : AppColors.muted, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(role['nameAr'] ?? '', style: TextStyle(color: isSelected ? color : AppColors.text, fontWeight: FontWeight.bold, fontSize: 14)),
                        if (role['description'] != null)
                          Text(role['description'], style: const TextStyle(color: AppColors.muted, fontSize: 10)),
                      ])),
                    ]),
                  ),
                );
              }).toList(),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء', style: TextStyle(color: AppColors.muted))),
              ElevatedButton(
                onPressed: () async {
                  if (selectedRole == null || selectedRole == user['role']) {
                    Navigator.pop(ctx);
                    return;
                  }
                  Navigator.pop(ctx);
                  try {
                    await ApiService.mutate('permissions.assignRole', input: {
                      'userId': user['id'],
                      'role': selectedRole,
                    });
                    _loadData();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم تغيير الدور بنجاح'), backgroundColor: Colors.green),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                child: const Text('حفظ', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────

  String _toSlug(String text) {
    final map = {'محاسب': 'accountant', 'مشرف': 'supervisor', 'موظف': 'staff', 'فني': 'technician', 'مبيعات': 'sales', 'دعم': 'support', 'مدير': 'manager'};
    for (final entry in map.entries) {
      if (text.contains(entry.key)) return entry.value;
    }
    return text.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
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
