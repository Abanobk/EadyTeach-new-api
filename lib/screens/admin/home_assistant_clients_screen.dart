import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';
import 'home_assistant_provision_screen.dart';

class HomeAssistantClientsScreen extends StatefulWidget {
  const HomeAssistantClientsScreen({super.key});

  @override
  State<HomeAssistantClientsScreen> createState() =>
      _HomeAssistantClientsScreenState();
}

class _HomeAssistantClientsScreenState extends State<HomeAssistantClientsScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 350), _load);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService.mutate(
        'admin.homeAssistant.listClients',
        input: {'q': _searchCtrl.text.trim(), 'limit': 250},
      );
      final data = res['data'];
      final items = data is Map ? data['items'] : null;
      final list = <Map<String, dynamic>>[];
      if (items is List) {
        for (final it in items) {
          if (it is Map) list.add(Map<String, dynamic>.from(it));
        }
      }
      if (!mounted) return;
      setState(() => _items = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEdit(Map<String, dynamic> row) async {
    final email = (row['email'] ?? '').toString();
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: RouteSettings(arguments: email),
        builder: (_) => const HomeAssistantProvisionScreen(),
      ),
    );
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Assistant Clients'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Container(
        decoration: AppThemeDecorations.gradientBackground(context),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search by email or name…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          onPressed: () => setState(() => _searchCtrl.text = ''),
                          icon: const Icon(Icons.clear_rounded),
                        ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: scheme.error),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final r = _items[i];
                            final enabled = r['enabled'] == true;
                            final name = (r['name'] ?? '').toString();
                            final email = (r['email'] ?? '').toString();
                            final haUrl = (r['haUrl'] ?? '').toString();
                            final tokenMasked = (r['tokenMasked'] ?? '').toString();

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: scheme.surface.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: enabled
                                      ? scheme.primary.withOpacity(0.35)
                                      : scheme.outline.withOpacity(0.25),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: enabled
                                          ? scheme.primary.withOpacity(0.18)
                                          : scheme.outline.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      enabled
                                          ? Icons.home_work_rounded
                                          : Icons.home_work_outlined,
                                      color: enabled
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name.isEmpty ? email : name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: scheme.onSurface,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          email,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: scheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          enabled
                                              ? 'Enabled • URL: $haUrl • Token: $tokenMasked'
                                              : 'Not provisioned',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: enabled
                                                ? scheme.primary
                                                : scheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  FilledButton.tonalIcon(
                                    onPressed: () => _openEdit(r),
                                    icon: const Icon(Icons.edit_rounded),
                                    label: const Text('Edit'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

