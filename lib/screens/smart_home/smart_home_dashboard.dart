import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/smart_home_provider.dart';
import '../../services/home_assistant_service.dart';
import '../../theme/app_theme.dart';

class SmartHomeDashboard extends StatefulWidget {
  const SmartHomeDashboard({super.key});

  @override
  State<SmartHomeDashboard> createState() => _SmartHomeDashboardState();
}

class _SmartHomeDashboardState extends State<SmartHomeDashboard> {
  String _selectedRoom = 'All';

  @override
  void initState() {
    super.initState();
    // Silent provisioning on entry (no HA login UI).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SmartHomeProvider>().initSilent();
    });
  }

  int _countLightsOn(List<HaEntity> entities) {
    return entities.where((e) => e.domain == 'light' && e.isOn).length;
  }

  IconData _iconForEntity(HaEntity e) {
    switch (e.domain) {
      case 'light':
        return Icons.lightbulb_rounded;
      case 'switch':
        return Icons.power_rounded;
      case 'fan':
        return Icons.toys_rounded;
      case 'climate':
        return Icons.ac_unit_rounded;
      case 'cover':
        return Icons.blinds_rounded;
      default:
        return Icons.device_unknown_rounded;
    }
  }

  String _statusForEntity(HaEntity e) {
    if (e.domain == 'light') {
      final b = e.brightness;
      if (b != null) {
        final pct = ((b / 255.0) * 100).round();
        return e.isOn ? '$pct%' : 'Off';
      }
    }
    if (e.domain == 'climate') {
      final t = e.temperature;
      if (t != null) return '${t.toStringAsFixed(0)}°';
    }
    return e.isOn ? 'On' : 'Off';
  }

  Future<void> _openDetails(HaEntity e) async {
    final smart = context.read<SmartHomeProvider>();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        if (e.domain == 'light') {
          final initial = (e.brightness ?? (e.isOn ? 200 : 0)).clamp(0, 255);
          double v = initial.toDouble();
          return StatefulBuilder(
            builder: (ctx, setSheet) => Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 10,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    e.friendlyName,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Brightness',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Slider(
                    value: v,
                    min: 0,
                    max: 255,
                    onChanged: (nv) => setSheet(() => v = nv),
                    onChangeEnd: (nv) =>
                        smart.setBrightness(e, nv.round().clamp(0, 255)),
                  ),
                  const SizedBox(height: 4),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                e.friendlyName,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No detailed controls for this device yet.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final smart = context.watch<SmartHomeProvider>();
    final scheme = Theme.of(context).colorScheme;
    final rooms = smart.buildRoomChips();
    if (!rooms.contains(_selectedRoom)) _selectedRoom = rooms.first;

    final entities = smart.entitiesForRoom(_selectedRoom);
    final lightsOn = _countLightsOn(smart.entities);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Home'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: smart.refreshStates,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Container(
        decoration: AppThemeDecorations.gradientBackground(context),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeaderCard(
                  title: 'Welcome, ${auth.userDisplayName}',
                  subtitle: smart.isEnabled
                      ? 'Status: $lightsOn Lights are On'
                      : 'Smart Home is not activated for this account',
                  isEnabled: smart.isEnabled,
                  isLoading: smart.isLoading,
                  error: smart.error,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: rooms.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final r = rooms[i];
                      final selected = r == _selectedRoom;
                      return ChoiceChip(
                        label: Text(r),
                        selected: selected,
                        onSelected: (_) => setState(() => _selectedRoom = r),
                        side: BorderSide(
                          color: selected
                              ? scheme.primary
                              : scheme.outline.withOpacity(0.4),
                        ),
                        selectedColor: scheme.primary.withOpacity(0.18),
                        labelStyle: TextStyle(
                          color: selected
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: !smart.isEnabled
                      ? _EmptyState(
                          title: 'Not provisioned',
                          subtitle:
                              'Ask the admin to add your Home Assistant URL + token.',
                          onRetry: smart.initSilent,
                        )
                      : GridView.builder(
                          itemCount: entities.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.08,
                          ),
                          itemBuilder: (context, index) {
                            final e = entities[index];
                            return _DeviceCard(
                              name: e.friendlyName,
                              icon: _iconForEntity(e),
                              status: _statusForEntity(e),
                              isOn: e.isOn,
                              onTap: () => smart.toggleEntity(e),
                              onLongPress: () => _openDetails(e),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isEnabled;
  final bool isLoading;
  final String? error;

  const _HeaderCard({
    required this.title,
    required this.subtitle,
    required this.isEnabled,
    required this.isLoading,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: scheme.surface.withOpacity(0.9),
        border: Border.all(color: scheme.outline.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isEnabled
                  ? scheme.primary.withOpacity(0.18)
                  : scheme.outline.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.home_work_rounded,
              color: isEnabled ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  error != null ? 'Error: $error' : subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: error != null
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (isLoading) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final String name;
  final IconData icon;
  final String status;
  final bool isOn;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _DeviceCard({
    required this.name,
    required this.icon,
    required this.status,
    required this.isOn,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = isOn
        ? scheme.primary.withOpacity(0.16)
        : scheme.surface.withOpacity(0.92);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: bg,
            border: Border.all(
              color: isOn
                  ? scheme.primary.withOpacity(0.35)
                  : scheme.outline.withOpacity(0.18),
            ),
            boxShadow: [
              if (isOn)
                BoxShadow(
                  color: scheme.primary.withOpacity(0.22),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                )
              else
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 10),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isOn
                          ? scheme.primary.withOpacity(0.22)
                          : scheme.outline.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      icon,
                      color: isOn ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Switch(
                    value: isOn,
                    onChanged: (_) => onTap(),
                    activeColor: scheme.primary,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  status,
                  style: TextStyle(
                    color: isOn ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onRetry;

  const _EmptyState({
    required this.title,
    required this.subtitle,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        padding: const EdgeInsets.all(18),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: scheme.surface.withOpacity(0.9),
          border: Border.all(color: scheme.outline.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.home_work_rounded, size: 44, color: scheme.primary),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

