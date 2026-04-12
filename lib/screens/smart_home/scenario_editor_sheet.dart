import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/scenario_provider.dart';
import '../../providers/smart_home_provider.dart';
import '../../smart_home/models/app_device.dart';
import '../../smart_home/models/scenario_model.dart';
import '../../smart_home/scenario_icons.dart';

Future<void> showScenarioEditorSheet(
  BuildContext context, {
  ScenarioModel? existing,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _ScenarioEditorBody(existing: existing),
  );
}

class _ScenarioEditorBody extends StatefulWidget {
  const _ScenarioEditorBody({this.existing});

  final ScenarioModel? existing;

  @override
  State<_ScenarioEditorBody> createState() => _ScenarioEditorBodyState();
}

class _ScenarioEditorBodyState extends State<_ScenarioEditorBody> {
  late final TextEditingController _nameCtrl;
  final List<ScenarioAction> _actions = [];
  late IconData _selectedIcon;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    if (widget.existing != null) {
      _actions.addAll(widget.existing!.actions);
    }
    final cp = widget.existing?.iconCodePoint;
    if (cp != null) {
      _selectedIcon =
          scenarioPickerIconMatchingCodePoint(cp) ?? scenarioIcons.first;
    } else {
      _selectedIcon = scenarioIcons.first;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDeviceAndService(SmartHomeProvider smart) async {
    final devices = smart.devices;
    if (devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No devices loaded yet. Refresh first.')),
      );
      return;
    }

    final action = await showDialog<ScenarioAction>(
      context: context,
      builder: (ctx) => _AddActionDialog(devices: devices),
    );
    if (action != null) {
      setState(() => _actions.add(action));
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a scenario name.')),
      );
      return;
    }
    if (_actions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one action.')),
      );
      return;
    }

    final id = widget.existing?.id ??
        DateTime.now().microsecondsSinceEpoch.toString();
    final model = ScenarioModel(
      id: id,
      name: name,
      actions: List<ScenarioAction>.from(_actions),
      iconCodePoint: _selectedIcon.codePoint,
    );
    await context.read<ScenarioProvider>().saveScenario(model);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final smart = context.watch<SmartHomeProvider>();
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.existing == null ? 'New scenario' : 'Edit scenario',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 14),
          _buildIconPicker(
            context,
            _selectedIcon,
            (icon) => setState(() => _selectedIcon = icon),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Actions',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _pickDeviceAndService(smart),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add'),
              ),
            ],
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: _actions.isEmpty
                ? Text(
                    'No actions yet.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _actions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (ctx, i) {
                      final a = _actions[i];
                      return Material(
                        color: scheme.surfaceContainerHighest.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(12),
                        child: ListTile(
                          dense: true,
                          title: Text(
                            a.entityId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            '${a.domain} · ${a.service}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () =>
                                setState(() => _actions.removeAt(i)),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _save,
            child: const Text('Save scenario'),
          ),
        ],
      ),
    );
  }

  Widget _buildIconPicker(
    BuildContext context,
    IconData selectedIcon,
    void Function(IconData) onIconSelected,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'اختر أيقونة للسيناريو:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 50,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: scenarioIcons.length,
            itemBuilder: (context, index) {
              final icon = scenarioIcons[index];
              final isSelected = icon.codePoint == selectedIcon.codePoint;
              return GestureDetector(
                onTap: () => onIconSelected(icon),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? scheme.primary
                        : scheme.surfaceContainerHighest.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected
                        ? Border.all(color: scheme.onPrimary, width: 2)
                        : null,
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? scheme.onPrimary : scheme.primary,
                    size: 28,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AddActionDialog extends StatefulWidget {
  const _AddActionDialog({required this.devices});

  final List<AppDevice> devices;

  @override
  State<_AddActionDialog> createState() => _AddActionDialogState();
}

class _AddActionDialogState extends State<_AddActionDialog> {
  AppDevice? _device;
  String _service = 'turn_on';

  @override
  void initState() {
    super.initState();
    if (widget.devices.isNotEmpty) {
      _device = widget.devices.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add action'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<AppDevice>(
              decoration: const InputDecoration(
                labelText: 'Device',
                border: OutlineInputBorder(),
              ),
              isExpanded: true,
              value: _device,
              items: widget.devices
                  .map(
                    (d) => DropdownMenuItem(
                      value: d,
                      child: Text(
                        d.friendlyName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (d) => setState(() => _device = d),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Service',
                border: OutlineInputBorder(),
              ),
              value: _service,
              items: const [
                DropdownMenuItem(value: 'turn_on', child: Text('turn_on')),
                DropdownMenuItem(value: 'turn_off', child: Text('turn_off')),
              ],
              onChanged: (v) => setState(() => _service = v ?? 'turn_on'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _device == null
              ? null
              : () {
                  final d = _device!;
                  Navigator.pop(
                    context,
                    ScenarioAction(
                      entityId: d.entityId,
                      domain: d.domain,
                      service: _service,
                    ),
                  );
                },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
