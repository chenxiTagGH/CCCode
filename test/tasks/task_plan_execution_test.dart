import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/tasks/task_plan.dart';

class _EventKernel implements AgentKernel {
  _EventKernel(this.descriptor, this.events);

  @override
  final KernelDescriptor descriptor;
  @override
  final Stream<KernelEvent> events;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

ChatSession _session(Stream<KernelEvent> events) {
  late final KernelDescriptor descriptor;
  descriptor = KernelDescriptor(
    id: 'task-test',
    label: 'Task test',
    icon: Icons.task_alt,
    description: '',
    create: (_) => _EventKernel(descriptor, events),
  );
  final session = ChatSession(
    kernel: descriptor,
    kernels: [descriptor],
    historyCount: 0,
  );
  addTearDown(session.dispose);
  return session;
}

void main() {
  test('projects a non-empty TodoWrite report and starts it', () async {
    final events = StreamController<KernelEvent>.broadcast(sync: true);
    addTearDown(events.close);
    final session = _session(events.stream);

    events.add(const TodosReported(1, [
      TodoEntry('Inspect the project', TodoStatus.inProgress),
      TodoEntry('Run focused tests', TodoStatus.pending),
    ]));

    expect(session.taskPlan, isNotNull);
    expect(session.taskPlan!.status, TaskPlanStatus.running);
    expect(session.taskPlan!.currentStep!.title, 'Inspect the project');
  });

  test('interrupted turns request a pause without completing steps', () async {
    final events = StreamController<KernelEvent>.broadcast(sync: true);
    addTearDown(events.close);
    final session = _session(events.stream);

    events.add(const TodosReported(1, [
      TodoEntry('Make the change', TodoStatus.inProgress),
      TodoEntry('Verify it', TodoStatus.pending),
    ]));
    events.add(const TurnStarted(2, 'turn'));
    events.add(const TurnEnded(3, 'turn', interrupted: true));

    expect(session.taskPlan!.status, TaskPlanStatus.running);
    expect(session.taskPlan!.pauseRequested, isTrue);
    expect(session.taskPlan!.completedCount, 0);
  });

  test('an empty todo report leaves ordinary chat without a task plan', () {
    final events = StreamController<KernelEvent>.broadcast(sync: true);
    addTearDown(events.close);
    final session = _session(events.stream);

    events.add(const TodosReported(1, []));

    expect(session.taskPlan, isNull);
  });
}
