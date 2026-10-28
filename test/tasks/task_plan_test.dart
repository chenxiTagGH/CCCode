import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/tasks/task_plan.dart';
import 'package:baocode/tasks/task_plan_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late TaskPlanController controller;

  setUp(() {
    now = DateTime(2026, 10, 29, 10);
    controller = TaskPlanController(now: () => now);
  });

  TaskStep step(String id, [String? title]) => TaskStep(
    id: id,
    title: title ?? id,
    estimateMin: const Duration(seconds: 10),
    estimateMax: const Duration(seconds: 30),
  );

  test('starts and records elapsed time from injected clock', () {
    controller.create(title: 'Ship', steps: [step('one'), step('two')]);
    controller.start();
    now = now.add(const Duration(seconds: 12));
    controller.completeStep();

    expect(controller.value!.steps[0].status, TaskStepStatus.completed);
    expect(controller.value!.steps[0].elapsed, const Duration(seconds: 12));
    expect(controller.value!.status, TaskPlanStatus.pending);
    expect(controller.value!.steps[1].status, TaskStepStatus.pending);
  });

  test('resuming a paused running step keeps it running', () {
    controller.create(steps: [step('one'), step('two')]);
    controller.start();
    controller.pause();
    controller.resume();

    expect(controller.value!.status, TaskPlanStatus.running);
    expect(controller.value!.steps[0].status, TaskStepStatus.running);
    expect(controller.value!.pauseRequested, isFalse);
  });

  test('pause lets current step finish and blocks the next step', () {
    controller.create(steps: [step('one'), step('two')]);
    controller.start();
    controller.pause();
    now = now.add(const Duration(seconds: 4));
    controller.completeStep();

    expect(controller.value!.status, TaskPlanStatus.paused);
    expect(controller.value!.steps[0].status, TaskStepStatus.completed);
    expect(controller.value!.steps[1].status, TaskStepStatus.pending);
    expect(controller.value!.pauseRequested, isTrue);

    controller.resume();
    expect(controller.value!.status, TaskPlanStatus.running);
    expect(controller.value!.steps[1].status, TaskStepStatus.running);
  });

  test('failure pauses execution and retry resets only failed step', () {
    controller.create(steps: [step('one'), step('two')]);
    controller.start();
    controller.completeStep();
    controller.start();
    controller.failStep('network');

    expect(controller.value!.status, TaskPlanStatus.failed);
    expect(controller.value!.steps[0].status, TaskStepStatus.completed);
    expect(controller.value!.steps[1].error, 'network');

    controller.retryFailed();
    expect(controller.value!.steps[0].status, TaskStepStatus.completed);
    expect(controller.value!.steps[1].status, TaskStepStatus.running);
  });

  test('cancel preserves completed steps and marks remaining steps', () {
    controller.create(steps: [step('one'), step('two')]);
    controller.start();
    controller.completeStep();
    controller.start();
    controller.cancel();

    expect(controller.value!.status, TaskPlanStatus.cancelled);
    expect(controller.value!.steps[0].status, TaskStepStatus.completed);
    expect(controller.value!.steps[1].status, TaskStepStatus.cancelled);
  });

  test('round trips JSON and recovers running work as paused', () {
    controller.create(steps: [step('one')]);
    controller.start();
    now = now.add(const Duration(seconds: 5));
    final json = controller.value!.toJson(at: now);
    final restored = TaskPlan.fromJson(json, recoverRunning: true);

    expect(restored!.status, TaskPlanStatus.paused);
    expect(restored.steps.single.status, TaskStepStatus.paused);
    expect(restored.steps.single.elapsed, const Duration(seconds: 5));
  });

  test('reconcile projects only agent todo events', () {
    controller.reconcile([
      const TodoEntry('Install', TodoStatus.inProgress),
      const TodoEntry('Test', TodoStatus.pending),
    ]);

    expect(controller.value!.steps.single.status, TaskStepStatus.running);
    controller.reconcile([
      const TodoEntry('Install', TodoStatus.completed),
      const TodoEntry('Test', TodoStatus.inProgress),
    ]);
    expect(controller.value!.steps[0].status, TaskStepStatus.completed);
    expect(controller.value!.steps[1].status, TaskStepStatus.running);
  });

  test('rejects malformed plans without creating state', () {
    expect(TaskPlan.fromJson({'version': 1, 'steps': []}), isNull);
    expect(TaskPlan.fromJson({'version': 1, 'title': 'x', 'steps': 'bad'}), isNull);
    controller.create(title: '', steps: [step('one')]);
    expect(controller.value, isNull);
  });
}
