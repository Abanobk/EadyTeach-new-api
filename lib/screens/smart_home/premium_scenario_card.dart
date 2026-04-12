import 'package:flutter/material.dart';

import '../../smart_home/models/scenario_model.dart';
import '../../smart_home/scenario_icons.dart';

/// Premium-style scenario chip; [isRunning] should come from [ScenarioProvider].
class PremiumScenarioCard extends StatelessWidget {
  final ScenarioModel scenario;
  final bool isRunning;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const PremiumScenarioCard({
    super.key,
    required this.scenario,
    this.isRunning = false,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cardBg = theme.cardTheme.color ?? cs.surface;

    return InkWell(
      onTap: isRunning ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 150,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isRunning ? cs.primary.withOpacity(0.1) : cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRunning ? cs.primary : theme.dividerColor.withOpacity(0.1),
            width: isRunning ? 2 : 1,
          ),
          boxShadow: [
            if (!isRunning)
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            isRunning
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                    ),
                  )
                : Icon(
                    scenarioDisplayIcon(scenario),
                    size: 32,
                    color: cs.primary,
                  ),
            const SizedBox(height: 12),
            Text(
              scenario.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: isRunning ? cs.primary : null,
              ),
            ),
            if (onEdit != null || onDelete != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (onEdit != null)
                    IconButton(
                      tooltip: 'Edit',
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                      onPressed: isRunning ? null : onEdit,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 32,
                      ),
                    ),
                  if (onDelete != null)
                    IconButton(
                      tooltip: 'Delete',
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                      onPressed: isRunning ? null : onDelete,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 32,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
