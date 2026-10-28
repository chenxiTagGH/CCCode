import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'task_plan.dart';

class TaskPlanIndicator extends StatelessWidget {
  const TaskPlanIndicator({
    super.key,
    required this.plan,
    required this.onTap,
  });

  final TaskPlan plan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = switch (plan.status) {
      TaskPlanStatus.pending => l10n.taskPlanPending,
      TaskPlanStatus.running => l10n.taskPlanRunning,
      TaskPlanStatus.completed => l10n.taskPlanCompleted,
      TaskPlanStatus.failed => l10n.taskPlanFailed,
      TaskPlanStatus.paused => l10n.taskPlanPaused,
      TaskPlanStatus.cancelled => l10n.taskPlanCancelled,
    };
    final color = switch (plan.status) {
      TaskPlanStatus.completed => Colors.green,
      TaskPlanStatus.failed => Colors.red,
      TaskPlanStatus.paused => Colors.orange,
      TaskPlanStatus.cancelled => Colors.grey,
      TaskPlanStatus.running => Theme.of(context).colorScheme.primary,
      TaskPlanStatus.pending => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    final current = plan.currentStep;
    final progress = current?.status == TaskStepStatus.running
        ? ' · ${l10n.taskPlanElapsed(current.elapsedAt(DateTime.now()))}'
        : '';
    return Semantics(
      button: true,
      label: '$status, ${plan.completedCount}/${plan.steps.length}$progress',
      child: Tooltip(
        message: l10n.taskPlanOpen,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.task_alt, size: 15, color: color),
                  const SizedBox(width: 6),
                  Text(
                    '$status · ${plan.completedCount}/${plan.steps.length}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
