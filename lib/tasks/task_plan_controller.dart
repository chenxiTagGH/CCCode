import 'package:flutter/foundation.dart';

import '../kernel/kernel_types.dart';
import 'task_plan.dart';
import 'task_plan_store.dart';

/// Records the existing agent's work; it never executes a step itself.
class TaskPlanController extends ValueNotifier<TaskPlan?> {
  TaskPlanController({
    DateTime Function()? now,
    this.store,
    this.storageKey,
  }) : _now = now ?? DateTime.now,
       super(null);

  final DateTime Function() _now;
  final TaskPlanStore? store;
  String? storageKey;
  int _revision = 0;
  bool _disposed = false;

  Future<void> restore() async {
    final key = storageKey;
    if (key == null || store == null) return;
    final revision = _revision;
    final restored = await store!.read(key);
    if (!_disposed && revision == _revision && restored != null) {
      value = restored;
    }
  }

  void _set(TaskPlan plan) {
    if (_disposed) return;
    _revision++;
    value = plan;
    final key = storageKey;
    if (key != null) store?.write(key, plan, at: _now());
  }

  Future<void> flush() => store?.flush() ?? Future<void>.value();

  void create({String title = 'Task plan', required List<TaskStep> steps}) {
    if (title.trim().isEmpty || steps.isEmpty) return;
    if (steps.any((step) => step.id.isEmpty || step.title.trim().isEmpty)) return;
    if (steps.map((step) => step.id).toSet().length != steps.length) return;
    _set(TaskPlan(title: title, steps: steps));
  }

  void start([String? stepId]) {
    final plan = value;
    if (plan == null ||
        plan.pauseRequested ||
        plan.status == TaskPlanStatus.paused ||
        plan.status == TaskPlanStatus.failed ||
        plan.status == TaskPlanStatus.cancelled ||
        plan.status == TaskPlanStatus.completed ||
        plan.steps.any((step) => step.status == TaskStepStatus.running)) {
      return;
    }
    final next = plan.steps
        .where((step) => step.status == TaskStepStatus.pending)
        .firstOrNull;
    if (next == null || (stepId != null && stepId != next.id)) return;
    final now = _now();
    _set(plan.copyWith(
      status: TaskPlanStatus.running,
      startedAt: plan.startedAt ?? now,
      finishedAt: null,
      steps: [
        for (final step in plan.steps)
          if (step.id == next.id)
            step.copyWith(
              status: TaskStepStatus.running,
              startedAt: step.startedAt ?? now,
              runningSince: now,
              finishedAt: null,
              error: null,
            )
          else
            step,
      ],
    ));
  }

  void completeStep([String? stepId]) {
    final plan = value;
    if (plan == null || plan.status == TaskPlanStatus.cancelled) return;
    final step = plan.steps
        .where((step) => step.id == (stepId ?? plan.currentStep?.id))
        .firstOrNull;
    if (step == null ||
        step.status == TaskStepStatus.completed ||
        step.status == TaskStepStatus.cancelled) return;
    final now = _now();
    final steps = [
      for (final item in plan.steps)
        if (item.id == step.id)
          item.copyWith(
            status: TaskStepStatus.completed,
            elapsed: item.elapsedAt(now),
            runningSince: null,
            finishedAt: now,
            error: null,
          )
        else
          item,
    ];
    final done = steps.every((step) => step.status == TaskStepStatus.completed);
    _set(plan.copyWith(
      steps: steps,
      status: done
          ? TaskPlanStatus.completed
          : plan.pauseRequested || plan.status == TaskPlanStatus.paused
              ? TaskPlanStatus.paused
              : TaskPlanStatus.pending,
      pauseRequested: !done && plan.pauseRequested,
      finishedAt: done ? now : null,
    ));
  }

  void failStep(String error, {String? stepId}) {
    final plan = value;
    if (plan == null || plan.status == TaskPlanStatus.cancelled) return;
    final target = stepId ?? plan.currentStep?.id;
    if (!plan.steps.any((step) => step.id == target &&
        step.status != TaskStepStatus.completed &&
        step.status != TaskStepStatus.cancelled)) return;
    final now = _now();
    _set(plan.copyWith(
      status: TaskPlanStatus.failed,
      pauseRequested: false,
      steps: [
        for (final step in plan.steps)
          if (step.id == target)
            step.copyWith(
              status: TaskStepStatus.failed,
              elapsed: step.elapsedAt(now),
              runningSince: null,
              finishedAt: now,
              error: error,
            )
          else
            step,
      ],
    ));
  }

  /// Running work is allowed to finish; the next step remains blocked.
  void pause() {
    final plan = value;
    if (plan == null ||
        plan.status == TaskPlanStatus.completed ||
        plan.status == TaskPlanStatus.cancelled ||
        plan.status == TaskPlanStatus.failed) return;
    final running = plan.steps.any((step) => step.status == TaskStepStatus.running);
    _set(plan.copyWith(
      status: running ? TaskPlanStatus.running : TaskPlanStatus.paused,
      pauseRequested: running,
    ));
  }

  void resume() {
    final plan = value;
    if (plan == null ||
        plan.status == TaskPlanStatus.cancelled ||
        plan.status == TaskPlanStatus.completed ||
        plan.status == TaskPlanStatus.failed) return;
    _set(plan.copyWith(
      status: TaskPlanStatus.pending,
      pauseRequested: false,
      steps: [
        for (final step in plan.steps)
          if (step.status == TaskStepStatus.paused)
            step.copyWith(status: TaskStepStatus.pending)
          else
            step,
      ],
    ));
    start();
  }

  void cancel() {
    final plan = value;
    if (plan == null ||
        plan.status == TaskPlanStatus.completed ||
        plan.status == TaskPlanStatus.cancelled) return;
    final now = _now();
    _set(plan.copyWith(
      status: TaskPlanStatus.cancelled,
      pauseRequested: false,
      finishedAt: now,
      steps: [
        for (final step in plan.steps)
          if (step.status != TaskStepStatus.completed)
            step.copyWith(
              status: TaskStepStatus.cancelled,
              elapsed: step.elapsedAt(now),
              runningSince: null,
              finishedAt: now,
            )
          else
            step,
      ],
    ));
  }

  void retryFailed() {
    final plan = value;
    if (plan == null || plan.status != TaskPlanStatus.failed) return;
    _set(plan.copyWith(
      status: TaskPlanStatus.pending,
      pauseRequested: false,
      steps: [
        for (final step in plan.steps)
          if (step.status == TaskStepStatus.failed)
            step.copyWith(
              status: TaskStepStatus.pending,
              finishedAt: null,
              error: null,
            )
          else
            step,
      ],
    ));
    start();
  }

  /// A validated, complete todo snapshot from the agent's own tool events.
  /// Updates completion only from those events, never from a timer.
  void reconcile(List<TodoEntry> todos, {String? title}) {
    if (todos.isEmpty || todos.any((todo) => todo.content.trim().isEmpty)) return;
    final previous = value;
    if (previous?.status == TaskPlanStatus.cancelled) return;
    final available = [...?previous?.steps];
    final steps = <TaskStep>[];
    for (final (index, todo) in todos.indexed) {
      final match = available
          .where((step) => step.title == todo.content)
          .firstOrNull;
      if (match != null) available.remove(match);
      final step = match ??
          TaskStep(id: 'step-${_revision + 1}-$index', title: todo.content);
      steps.add(
        todo.status == TodoStatus.pending && step.status == TaskStepStatus.running
            ? step.copyWith(
                status: TaskStepStatus.pending,
                elapsed: step.elapsedAt(_now()),
                runningSince: null,
              )
            : step,
      );
    }
    if (previous == null) {
      create(title: title ?? 'Task plan', steps: steps);
    } else {
      _set(previous.copyWith(title: title, steps: steps));
    }
    for (final (index, todo) in todos.indexed) {
      if (todo.status == TodoStatus.completed) completeStep(steps[index].id);
    }
    final plan = value;
    if (plan == null ||
        plan.status == TaskPlanStatus.paused ||
        plan.status == TaskPlanStatus.failed ||
        plan.status == TaskPlanStatus.cancelled ||
        plan.pauseRequested) return;
    final active = todos.indexed
        .where((entry) => entry.$2.status == TodoStatus.inProgress)
        .firstOrNull;
    if (active != null) {
      start(steps[active.$1].id);
    } else if (plan.steps.any((step) => step.status == TaskStepStatus.pending)) {
      // A TodoWrite update may briefly mark the previous step complete before
      // marking the next one in progress; advance the projection immediately.
      start();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
