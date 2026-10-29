import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'task_plan.dart';

class TaskPlanDrawer extends StatelessWidget {
  const TaskPlanDrawer({
    super.key,
    required this.plan,
    required this.onClose,
    this.onPause,
    this.onResume,
    this.onRetry,
    this.onStop,
  });

  final TaskPlan plan;
  final VoidCallback onClose;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onRetry;
  final VoidCallback? onStop;

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
    return Material(
      elevation: 12,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            width: math.min(350.0, constraints.maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                title: Text(plan.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '$status · ${plan.completedCount}/${plan.steps.length} · '
                  '${l10n.taskPlanElapsed(
                    _TaskStepTile._formatDuration(plan.elapsedAt(DateTime.now())),
                  )}',
                ),
                trailing: IconButton(
                  tooltip: l10n.commonClose,
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: plan.steps.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _TaskStepTile(
                    step: plan.steps[index],
                    now: DateTime.now(),
                  ),
                ),
              ),
              _Controls(
                plan: plan,
                onPause: onPause,
                onResume: onResume,
                onRetry: onRetry,
                onStop: onStop,
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskStepTile extends StatelessWidget {
  const _TaskStepTile({required this.step, required this.now});

  final TaskStep step;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final icon = switch (step.status) {
      TaskStepStatus.completed => Icons.check_circle,
      TaskStepStatus.running => Icons.play_circle,
      TaskStepStatus.failed => Icons.error,
      TaskStepStatus.paused => Icons.pause_circle,
      TaskStepStatus.cancelled => Icons.cancel,
      TaskStepStatus.pending => Icons.radio_button_unchecked,
    };
    final color = switch (step.status) {
      TaskStepStatus.completed => Colors.green,
      TaskStepStatus.failed => Colors.red,
      TaskStepStatus.paused => Colors.orange,
      TaskStepStatus.cancelled => Colors.grey,
      TaskStepStatus.running => Theme.of(context).colorScheme.primary,
      TaskStepStatus.pending => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    final detail = switch (step.status) {
      TaskStepStatus.pending => _estimate(step, l10n),
      TaskStepStatus.running => l10n.taskPlanElapsed(_formatDuration(step.elapsedAt(now))),
      TaskStepStatus.completed => l10n.taskPlanStepCompleted(_formatDuration(step.elapsedAt(now))),
      TaskStepStatus.failed => step.error == null
          ? l10n.taskPlanStepFailed(_formatDuration(step.elapsedAt(now)))
          : '${l10n.taskPlanStepFailed(_formatDuration(step.elapsedAt(now)))}: ${step.error}',
      TaskStepStatus.paused => l10n.taskPlanStepPaused(_formatDuration(step.elapsedAt(now))),
      TaskStepStatus.cancelled => l10n.taskPlanStepCancelled,
    };
    return Semantics(
      container: true,
      label: '${step.title}, $detail',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 18, color: color)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(detail, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _estimate(TaskStep step, AppLocalizations l10n) {
    final min = step.estimateMin;
    final max = step.estimateMax;
    if (min == null && max == null) return l10n.taskPlanEstimateUnknown;
    return l10n.taskPlanEstimate(_formatDuration(min ?? max!), _formatDuration(max ?? min!));
  }

  static String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds;
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return rest == 0 ? '${minutes}m' : '${minutes}m ${rest}s';
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.plan, this.onPause, this.onResume, this.onRetry, this.onStop});

  final TaskPlan plan;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onRetry;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canStop = onStop != null &&
        plan.status != TaskPlanStatus.completed &&
        plan.status != TaskPlanStatus.cancelled;
    final canPause = onPause != null &&
        (plan.status == TaskPlanStatus.running || plan.status == TaskPlanStatus.pending);
    final canResume = onResume != null && plan.status == TaskPlanStatus.paused;
    final canRetry = onRetry != null && plan.status == TaskPlanStatus.failed;
    if (!canStop && !canPause && !canResume && !canRetry) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (canPause)
            OutlinedButton.icon(onPressed: onPause, icon: const Icon(Icons.pause), label: Text(l10n.taskPlanPause)),
          if (canResume)
            FilledButton.icon(onPressed: onResume, icon: const Icon(Icons.play_arrow), label: Text(l10n.taskPlanResume)),
          if (canRetry)
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(l10n.taskPlanRetry)),
          if (canStop)
            TextButton.icon(onPressed: () => _confirmStop(context), icon: const Icon(Icons.stop), label: Text(l10n.taskPlanStop)),
        ],
      ),
    );
  }

  Future<void> _confirmStop(BuildContext context) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.taskPlanStop),
        content: Text(l10n.taskPlanStopConfirmation),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.taskPlanStop)),
        ],
      ),
    );
    if (confirmed == true) onStop?.call();
  }
}
