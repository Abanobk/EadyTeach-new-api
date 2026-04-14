import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/scenario_provider.dart';
import '../../providers/smart_home_provider.dart';
import '../../smart_home/models/app_device.dart';
import '../../smart_home/models/scenario_model.dart';
import '../../utils/theme_modern.dart';
import 'premium_scenario_card.dart';
import 'scenario_editor_sheet.dart';

class SmartHomeDashboard extends StatefulWidget {
  const SmartHomeDashboard({super.key});

  @override
  State<SmartHomeDashboard> createState() => _SmartHomeDashboardState();
}

class _SmartHomeDashboardState extends State<SmartHomeDashboard> {
  String _selectedFloor = 'All';
  String _selectedRoom = 'All';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SmartHomeProvider>().initSilent();
      context.read<ScenarioProvider>().ensureInitialized();
    });
  }

  Future<void> _runScenario(BuildContext context, ScenarioModel s) async {
    final sp = context.read<ScenarioProvider>();
    await sp.runScenario(s);
    if (!context.mounted) return;
    final err = sp.error;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ran "${s.name}"')),
      );
    }
  }

  Future<void> _confirmDeleteScenario(
    BuildContext context,
    ScenarioModel s,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete scenario'),
        content: Text('Delete "${s.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<ScenarioProvider>().deleteScenario(s.id);
    }
  }

  int _countLightsOn(List<AppDevice> entities) {
    return entities.where((e) => e.domain == 'light' && e.isOn).length;
  }

  int _countActiveDevices(List<AppDevice> entities) {
    return entities.where((e) => e.isOn).length;
  }

  int _uniquePlacedRoomCount(List<AppDevice> entities) {
    final keys = <String>{};
    for (final e in entities) {
      if (!e.isPlaced) continue;
      keys.add('${e.floorName}__${e.roomName}');
    }
    return keys.length;
  }

  IconData _iconForEntity(AppDevice e) {
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
      case 'lock':
        return Icons.lock_rounded;
      default:
        return Icons.device_unknown_rounded;
    }
  }

  String _domainLabel(AppDevice e) {
    switch (e.domain) {
      case 'light':
        return 'Light';
      case 'switch':
        return 'Switch';
      case 'fan':
        return 'Fan';
      case 'climate':
        return 'Climate';
      case 'cover':
        return 'Curtain';
      case 'lock':
        return 'Lock';
      default:
        return 'Device';
    }
  }

  String _statusForEntity(AppDevice e) {
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

  Future<void> _openEditLocation(AppDevice d) async {
    final smart = context.read<SmartHomeProvider>();
    final floorCtrl = TextEditingController(text: d.floorName);
    final roomCtrl = TextEditingController(text: d.roomName);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: bottom + 16,
          ),
          child: GlassCard(
            borderRadius: 28,
            tintColor: Colors.white,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Edit location',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColorsModern.primary,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  d.friendlyName,
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: AppColorsModern.textSecondary,
                      ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: floorCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Floor',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: roomCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Room',
                    hintText: 'Use "Unassigned" for the default bucket',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () async {
                    await smart.assignToRoom(
                      entityId: d.entityId,
                      floorName: floorCtrl.text,
                      roomName: roomCtrl.text,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Save location'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    await smart.unassignDevice(d.entityId);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Reset to General / Unassigned'),
                ),
              ],
            ),
          ),
        );
      },
    );
    floorCtrl.dispose();
    roomCtrl.dispose();
  }

  Future<void> _openDetails(AppDevice e) async {
    final smart = context.read<SmartHomeProvider>();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        if (e.domain == 'light') {
          final initial = (e.brightness ?? (e.isOn ? 200 : 0)).clamp(0, 255);
          double v = initial.toDouble();
          return StatefulBuilder(
            builder: (ctx, setSheet) => Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: GlassCard(
                borderRadius: 28,
                tintColor: Colors.white,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _MiniIconBubble(
                          icon: _iconForEntity(e),
                          color: AppColorsModern.accent,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.friendlyName,
                                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: AppColorsModern.primary,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${e.floorName} · ${e.roomName}',
                                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                      color: AppColorsModern.textSecondary,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Brightness',
                      style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                            color: AppColorsModern.textSecondary,
                          ),
                    ),
                    Slider(
                      value: v,
                      min: 0,
                      max: 255,
                      activeColor: AppColorsModern.accent,
                      onChanged: (nv) => setSheet(() => v = nv),
                      onChangeEnd: (nv) =>
                          smart.setBrightness(e, nv.round().clamp(0, 255)),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await _openEditLocation(e);
                            },
                            icon: const Icon(Icons.edit_location_alt_rounded, size: 18),
                            label: const Text('Edit location'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Done'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: GlassCard(
            borderRadius: 28,
            tintColor: Colors.white,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _MiniIconBubble(
                      icon: _iconForEntity(e),
                      color: e.isOn ? AppColorsModern.accent : AppColorsModern.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.friendlyName,
                            style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: AppColorsModern.primary,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${e.floorName} · ${e.roomName}',
                            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                  color: AppColorsModern.textSecondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'No detailed controls for this device yet.',
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: AppColorsModern.textSecondary,
                      ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _openEditLocation(e);
                        },
                        icon: const Icon(Icons.edit_location_alt_rounded, size: 18),
                        label: const Text('Edit location'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final smart = context.watch<SmartHomeProvider>();
    final scenarios = context.watch<ScenarioProvider>();

    final floors = ['All', ...smart.floorNames()];
    final floorOk = floors.contains(_selectedFloor);
    if (!floorOk) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _selectedFloor = floors.first;
          _selectedRoom = 'All';
        });
      });
    }
    final floor = floorOk ? _selectedFloor : floors.first;
    final rooms = floor == 'All'
        ? <String>['All']
        : ['All', ...smart.roomNamesForFloor(floor)];
    final roomOk = rooms.contains(_selectedRoom);
    if (!roomOk) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedRoom = rooms.first);
      });
    }
    final room = roomOk ? _selectedRoom : rooms.first;

    final unassigned = smart.unassignedDevices;
    final assignedEntities = smart.devicesForFloorAndRoom(floor, room);
    final lightsOn = _countLightsOn(smart.devices);
    final activeDevices = _countActiveDevices(smart.devices);
    final showFilterHint = assignedEntities.isEmpty &&
        smart.placedDevices.isNotEmpty &&
        (floor != 'All' || room != 'All');

    return Scaffold(
      backgroundColor: AppColorsModern.primary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Smart Home',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (smart.isEnabled)
            IconButton(
              tooltip: 'New scenario',
              onPressed: () => showScenarioEditorSheet(context),
              icon: const Icon(Icons.add_task_rounded),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: smart.isEnabled ? smart.refreshStates : smart.initSilent,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF06162D),
              Color(0xFF0A1F3E),
              Color(0xFF10294F),
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -120,
              right: -60,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColorsModern.accent.withOpacity(0.16),
                ),
              ),
            ),
            Positioned(
              bottom: -100,
              left: -60,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.07),
                ),
              ),
            ),
            SafeArea(
              child: RefreshIndicator(
                color: AppColorsModern.accent,
                onRefresh: smart.isEnabled ? smart.refreshStates : smart.initSilent,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          _HeroHeader(
                            userName: auth.userDisplayName,
                            isEnabled: smart.isEnabled,
                            isLoading: smart.isLoading,
                            error: smart.error,
                            lightsOn: lightsOn,
                            activeDevices: activeDevices,
                            totalDevices: smart.devices.length,
                            floorCount: smart.floorNames().length,
                            roomCount: _uniquePlacedRoomCount(smart.devices),
                            scenarioCount: scenarios.scenarios.length,
                          ),
                          const SizedBox(height: 18),
                          if (smart.isEnabled) ...[
                            _SectionShell(
                              title: 'Quick scenes',
                              subtitle: scenarios.scenarios.isEmpty
                                  ? 'Create one-tap routines to control multiple devices together.'
                                  : 'Run or edit your saved scenes instantly without changing the connection logic.',
                              trailing: IconButton(
                                tooltip: 'New scenario',
                                onPressed: () => showScenarioEditorSheet(context),
                                icon: const Icon(Icons.add_circle_outline_rounded),
                                color: Colors.white,
                              ),
                              child: scenarios.isLoading && scenarios.scenarios.isEmpty
                                  ? const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 10),
                                      child: LinearProgressIndicator(),
                                    )
                                  : scenarios.scenarios.isEmpty
                                      ? _InlineCallout(
                                          icon: Icons.auto_awesome_rounded,
                                          title: 'No scenes yet',
                                          subtitle: 'Use the add button to create a lighting, curtain, or all-off scene.',
                                          actionLabel: 'Create scene',
                                          onPressed: () => showScenarioEditorSheet(context),
                                        )
                                      : SizedBox(
                                          height: 168,
                                          child: ListView.separated(
                                            scrollDirection: Axis.horizontal,
                                            itemCount: scenarios.scenarios.length,
                                            separatorBuilder: (_, __) => const SizedBox(width: 10),
                                            itemBuilder: (ctx, i) {
                                              final s = scenarios.scenarios[i];
                                              return PremiumScenarioCard(
                                                scenario: s,
                                                isRunning: scenarios.isScenarioRunning(s.id),
                                                onTap: () => _runScenario(context, s),
                                                onEdit: () => showScenarioEditorSheet(
                                                  context,
                                                  existing: s,
                                                ),
                                                onDelete: () => _confirmDeleteScenario(context, s),
                                              );
                                            },
                                          ),
                                        ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          _SectionShell(
                            title: 'Browse by space',
                            subtitle: 'Filter devices by floor and room for a faster and cleaner control experience.',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _FilterGroup(
                                  label: 'Floor',
                                  items: floors,
                                  selectedValue: floor,
                                  onSelected: (value) => setState(() {
                                    _selectedFloor = value;
                                    _selectedRoom = 'All';
                                  }),
                                ),
                                const SizedBox(height: 14),
                                _FilterGroup(
                                  label: 'Room',
                                  items: rooms,
                                  selectedValue: room,
                                  onSelected: (value) => setState(() => _selectedRoom = value),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (!smart.isEnabled)
                            _PremiumEmptyState(
                              icon: Icons.home_work_rounded,
                              accent: AppColorsModern.accent,
                              title: 'Smart Home is not provisioned yet',
                              subtitle:
                                  'The connection flow with Home Assistant is kept unchanged. Once the admin adds the URL and token, this dashboard will immediately show your devices and rooms here in the new modern layout.',
                              actionLabel: 'Retry connection',
                              onPressed: smart.initSilent,
                            )
                          else if (smart.devices.isEmpty)
                            _PremiumEmptyState(
                              icon: Icons.devices_other_rounded,
                              accent: Colors.white,
                              title: 'No controllable devices found',
                              subtitle:
                                  'Pull to refresh or add compatible devices in Home Assistant. As soon as they appear, you can assign them to floors and rooms from this page.',
                              actionLabel: 'Refresh devices',
                              onPressed: smart.refreshStates,
                            )
                          else ...[
                            if (unassigned.isNotEmpty) ...[
                              _SectionShell(
                                title: 'New or unassigned devices',
                                subtitle: 'These devices are online but not yet attached to a room. Long-press or use the location icon to organize them.',
                                child: _DeviceGrid(
                                  devices: unassigned,
                                  iconForEntity: _iconForEntity,
                                  domainLabel: _domainLabel,
                                  statusForEntity: _statusForEntity,
                                  onToggle: (e) => smart.toggleDevice(e),
                                  onOpenDetails: _openDetails,
                                  onEditLocation: _openEditLocation,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            _SectionShell(
                              title: floor == 'All' && room == 'All'
                                  ? 'Your organized devices'
                                  : 'Devices in $floor${room == 'All' ? '' : ' · $room'}',
                              subtitle: floor == 'All' && room == 'All'
                                  ? 'A cleaner overview of all devices already assigned to rooms.'
                                  : 'Use the filters above to jump between areas without changing any connection settings.',
                              child: assignedEntities.isEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'No devices match this floor or room yet. Try selecting All or move devices from the unassigned section.',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              color: Colors.white70,
                                              height: 1.45,
                                            ),
                                      ),
                                    )
                                  : _DeviceGrid(
                                      devices: assignedEntities,
                                      iconForEntity: _iconForEntity,
                                      domainLabel: _domainLabel,
                                      statusForEntity: _statusForEntity,
                                      onToggle: (e) => smart.toggleDevice(e),
                                      onOpenDetails: _openDetails,
                                      onEditLocation: _openEditLocation,
                                    ),
                            ),
                            if (showFilterHint)
                              Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: Text(
                                  'No devices match this floor/room. Try switching both filters back to All.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Colors.white70,
                                      ),
                                ),
                              ),
                          ],
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  final String userName;
  final bool isEnabled;
  final bool isLoading;
  final String? error;
  final int lightsOn;
  final int activeDevices;
  final int totalDevices;
  final int floorCount;
  final int roomCount;
  final int scenarioCount;

  const _HeroHeader({
    required this.userName,
    required this.isEnabled,
    required this.isLoading,
    required this.error,
    required this.lightsOn,
    required this.activeDevices,
    required this.totalDevices,
    required this.floorCount,
    required this.roomCount,
    required this.scenarioCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.16),
            Colors.white.withOpacity(0.06),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 26,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: AppColorsModern.accent.withOpacity(0.16),
                  border: Border.all(color: AppColorsModern.accent.withOpacity(0.35)),
                ),
                child: const Icon(
                  Icons.home_rounded,
                  color: AppColorsModern.accent,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome, $userName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 28,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      error != null
                          ? 'Connection issue: $error'
                          : isEnabled
                              ? 'A modern control hub for your home devices, rooms, and quick scenes.'
                              : 'Your modern dashboard is ready and will activate as soon as Home Assistant credentials are provisioned.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withOpacity(0.82),
                            height: 1.45,
                          ),
                    ),
                  ],
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColorsModern.accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatPill(
                icon: Icons.wb_incandescent_rounded,
                label: 'Lights on',
                value: '$lightsOn',
                highlight: true,
              ),
              _StatPill(
                icon: Icons.power_settings_new_rounded,
                label: 'Active',
                value: '$activeDevices / $totalDevices',
              ),
              _StatPill(
                icon: Icons.layers_rounded,
                label: 'Floors',
                value: '$floorCount',
              ),
              _StatPill(
                icon: Icons.meeting_room_rounded,
                label: 'Rooms',
                value: '$roomCount',
              ),
              _StatPill(
                icon: Icons.auto_mode_rounded,
                label: 'Scenes',
                value: '$scenarioCount',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  const _StatPill({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: highlight
            ? AppColorsModern.accent.withOpacity(0.18)
            : Colors.white.withOpacity(0.08),
        border: Border.all(
          color: highlight
              ? AppColorsModern.accent.withOpacity(0.34)
              : Colors.white.withOpacity(0.10),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: highlight ? AppColorsModern.accent : Colors.white),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white70,
                    ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  const _SectionShell({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white.withOpacity(0.07),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                            height: 1.45,
                          ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _FilterGroup extends StatelessWidget {
  final String label;
  final List<String> items;
  final String selectedValue;
  final ValueChanged<String> onSelected;

  const _FilterGroup({
    required this.label,
    required this.items,
    required this.selectedValue,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((item) {
            final selected = item == selectedValue;
            return ChoiceChip(
              label: Text(item),
              selected: selected,
              onSelected: (_) => onSelected(item),
              backgroundColor: Colors.white.withOpacity(0.05),
              selectedColor: AppColorsModern.accent.withOpacity(0.18),
              side: BorderSide(
                color: selected
                    ? AppColorsModern.accent.withOpacity(0.45)
                    : Colors.white.withOpacity(0.10),
              ),
              labelStyle: TextStyle(
                color: selected ? AppColorsModern.accent : Colors.white,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _InlineCallout extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onPressed;

  const _InlineCallout({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          _MiniIconBubble(icon: icon, color: AppColorsModern.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                        height: 1.45,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: AppColorsModern.accent,
              foregroundColor: Colors.black,
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _DeviceGrid extends StatelessWidget {
  final List<AppDevice> devices;
  final IconData Function(AppDevice e) iconForEntity;
  final String Function(AppDevice e) domainLabel;
  final String Function(AppDevice e) statusForEntity;
  final Future<void> Function(AppDevice e) onOpenDetails;
  final Future<void> Function(AppDevice e) onEditLocation;
  final ValueChanged<AppDevice> onToggle;

  const _DeviceGrid({
    required this.devices,
    required this.iconForEntity,
    required this.domainLabel,
    required this.statusForEntity,
    required this.onOpenDetails,
    required this.onEditLocation,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 2;
        if (constraints.maxWidth >= 980) {
          crossAxisCount = 4;
        } else if (constraints.maxWidth >= 700) {
          crossAxisCount = 3;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: devices.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: constraints.maxWidth < 420 ? 0.90 : 1.02,
          ),
          itemBuilder: (context, index) {
            final e = devices[index];
            return _DeviceCard(
              name: e.friendlyName,
              subtitle: '${e.floorName} · ${e.roomName}',
              typeLabel: domainLabel(e),
              icon: iconForEntity(e),
              status: statusForEntity(e),
              isOn: e.isOn,
              onTap: () => onToggle(e),
              onLongPress: () => onOpenDetails(e),
              onEdit: () => onEditLocation(e),
            );
          },
        );
      },
    );
  }
}

class _MiniIconBubble extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _MiniIconBubble({
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: color.withOpacity(0.14),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Icon(icon, color: color),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final String name;
  final String? subtitle;
  final String typeLabel;
  final IconData icon;
  final String status;
  final bool isOn;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onEdit;

  const _DeviceCard({
    required this.name,
    this.subtitle,
    required this.typeLabel,
    required this.icon,
    required this.status,
    required this.isOn,
    required this.onTap,
    required this.onLongPress,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isOn
        ? AppColorsModern.accent.withOpacity(0.36)
        : Colors.white.withOpacity(0.10);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isOn
                  ? [
                      Colors.white.withOpacity(0.16),
                      AppColorsModern.accent.withOpacity(0.10),
                    ]
                  : [
                      Colors.white.withOpacity(0.09),
                      Colors.white.withOpacity(0.05),
                    ],
            ),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: isOn
                    ? AppColorsModern.accent.withOpacity(0.12)
                    : Colors.black.withOpacity(0.10),
                blurRadius: 20,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _MiniIconBubble(
                    icon: icon,
                    color: isOn ? AppColorsModern.accent : Colors.white,
                  ),
                  const Spacer(),
                  if (onEdit != null)
                    IconButton(
                      tooltip: 'Edit location',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      onPressed: onEdit,
                      icon: const Icon(
                        Icons.edit_location_alt_rounded,
                        size: 20,
                        color: Colors.white70,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: Colors.white.withOpacity(0.08),
                    ),
                    child: Text(
                      typeLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: isOn
                          ? AppColorsModern.accent.withOpacity(0.18)
                          : Colors.white.withOpacity(0.08),
                    ),
                    child: Text(
                      status,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: isOn ? AppColorsModern.accent : Colors.white70,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isOn ? 'Tap to turn off' : 'Tap to turn on',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white60,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  Switch(
                    value: isOn,
                    onChanged: (_) => onTap(),
                    activeColor: AppColorsModern.accent,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumEmptyState extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onPressed;

  const _PremiumEmptyState({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.11),
            Colors.white.withOpacity(0.05),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Column(
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: accent.withOpacity(0.14),
              border: Border.all(color: accent.withOpacity(0.30)),
            ),
            child: Icon(icon, size: 36, color: accent),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                  height: 1.55,
                ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: AppColorsModern.accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}
