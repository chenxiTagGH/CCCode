import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/claude_code/claude_sdk_tools.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/tasks/task_plan.dart';

import '../kernel_test.dart' show FakeCli;

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

ChatSession _claudeSession(FakeCli cli) {
  late final KernelDescriptor descriptor;
  descriptor = KernelDescriptor(
    id: 'claude-code',
    label: 'Claude Code',
    icon: Icons.task_alt,
    description: '',
    create: (context) =>
        ClaudeCodeKernel(descriptor, context, start: (_) async => cli),
  );
  final session = ChatSession(
    kernel: descriptor,
    kernels: [descriptor],
    historyCount: 0,
  );
  addTearDown(session.dispose);
  return session;
}

void _reportTasks(FakeCli cli, String id, String first, String second) {
  cli.push({
    'type': 'assistant',
    'message': {
      'role': 'assistant',
      'content': [
        {
          'type': 'tool_use',
          'id': id,
          'name': 'TodoWrite',
          'input': {
            'todos': [
              {'content': 'Make the change', 'status': first},
              {'content': 'Verify it', 'status': second},
            ],
          },
        },
      ],
    },
  });
}

class _RefusingCli extends FakeCli {
  @override
  void write(Map<String, Object?> message) {
    final request = message['request'];
    if (request is Map && request['subtype'] == 'interrupt') {
      written.add(message);
      push({
        'type': 'control_response',
        'response': {
          'subtype': 'error',
          'request_id': message['request_id'],
          'error': 'Cannot interrupt',
        },
      });
      return;
    }
    super.write(message);
  }
}

void main() {
  test(
    'the app task tool reports steps when native Claude task tools are absent',
    () async {
      ClaudeSdkTools.registerTaskList();
      addTearDown(() => ClaudeSdkTools.unregister(ClaudeSdkTools.taskListTool));
      final cli = FakeCli();
      final session = _claudeSession(cli);
      session.send(const ComposerMessage(text: 'Make and verify the change'));
      await pumpEventQueue();
      expect(
        cli.requests('initialize').single['sdkMcpServers'],
        contains('cccode'),
      );

      cli.push({
        'type': 'control_request',
        'request_id': 'report-tasks',
        'request': {
          'subtype': 'mcp_message',
          'server_name': 'cccode',
          'message': {
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'tools/call',
            'params': {
              'name': ClaudeSdkTools.taskListTool,
              'arguments': {
                'todos': [
                  {'content': 'Make the change', 'status': 'in_progress'},
                  {'content': 'Verify it', 'status': 'pending'},
                ],
              },
            },
          },
        },
      });
      await pumpEventQueue();

      expect(session.taskPlan!.steps.map((step) => step.title), [
        'Make the change',
        'Verify it',
      ]);
      expect(session.taskPlan!.status, TaskPlanStatus.running);
      expect(cli.responses.single['mcp_response'], {
        'jsonrpc': '2.0',
        'id': 1,
        'result': {
          'content': [
            {'type': 'text', 'text': 'Task list updated.'},
          ],
        },
      });
    },
  );

  test('a rejected interrupt leaves the task running', () async {
    final cli = _RefusingCli();
    final session = _claudeSession(cli);
    session.send(const ComposerMessage(text: 'Make and verify the change'));
    await pumpEventQueue();
    _reportTasks(cli, 'todo-1', 'in_progress', 'pending');
    await pumpEventQueue();

    await session.pauseTask();

    expect(cli.requests('interrupt'), hasLength(1));
    expect(session.isStreaming, isTrue);
    expect(session.taskPlan!.status, TaskPlanStatus.running);
    expect(session.taskPlan!.pauseRequested, isFalse);
    expect(session.canPauseTask, isTrue);
  });

  test('pause also waits for reported background work to end', () async {
    final cli = FakeCli();
    final session = _claudeSession(cli);
    session.send(const ComposerMessage(text: 'Make and verify the change'));
    await pumpEventQueue();
    _reportTasks(cli, 'todo-1', 'in_progress', 'pending');
    cli.push({
      'type': 'system',
      'subtype': 'task_started',
      'task_type': 'local_bash',
      'task_id': 'build',
      'is_backgrounded': true,
    });
    await pumpEventQueue();

    unawaited(session.pauseTask());
    await pumpEventQueue();
    cli.push({'type': 'result', 'subtype': 'error_during_execution'});
    await pumpEventQueue();
    expect(session.isStreaming, isFalse);
    expect(session.taskPlan!.pauseRequested, isTrue);
    expect(session.taskPlan!.status, isNot(TaskPlanStatus.paused));

    cli.push({
      'type': 'system',
      'subtype': 'task_notification',
      'task_id': 'build',
      'status': 'stopped',
    });
    await pumpEventQueue();
    expect(session.taskPlan!.status, TaskPlanStatus.paused);
  });

  test(
    'requesting the task list sends an instruction and uses real reports',
    () async {
      final cli = FakeCli();
      final session = _claudeSession(cli);
      session.requestTaskPlan();
      session.requestTaskPlan();
      await pumpEventQueue();
      expect(cli.users, hasLength(1));
      expect(cli.users.single['message'].toString(), contains('checklist'));
      expect(session.taskPlan, isNull);
      _reportTasks(cli, 'todo-1', 'pending', 'pending');
      await pumpEventQueue();

      expect(session.taskPlan!.steps, hasLength(2));
      expect(session.taskPlan!.status, TaskPlanStatus.pending);
      expect(session.taskPlan!.steps[0].status, TaskStepStatus.pending);
    },
  );

  test(
    'pause waits for the runtime result, including after the interrupt ack',
    () async {
      final cli = FakeCli();
      final session = _claudeSession(cli);
      session.send(const ComposerMessage(text: 'Make and verify the change'));
      await pumpEventQueue();
      _reportTasks(cli, 'todo-1', 'in_progress', 'pending');
      await pumpEventQueue();

      session.pauseTask();
      await pumpEventQueue();
      expect(cli.requests('interrupt'), hasLength(1));
      expect(session.isStreaming, isTrue);
      expect(session.taskPlan!.pauseRequested, isTrue);

      _reportTasks(cli, 'todo-2', 'completed', 'in_progress');
      await pumpEventQueue();
      expect(session.taskPlan!.status, TaskPlanStatus.running);
      expect(session.taskPlan!.pauseRequested, isTrue);

      cli.push({'type': 'result', 'subtype': 'error_during_execution'});
      await pumpEventQueue();
      expect(session.isStreaming, isFalse);
      expect(session.taskPlan!.status, TaskPlanStatus.paused);
      expect(session.taskPlan!.steps[0].status, TaskStepStatus.completed);
      expect(session.taskPlan!.steps[1].status, TaskStepStatus.paused);
    },
  );

  test(
    'continue waits for a new progress report before starting a step',
    () async {
      final cli = FakeCli();
      final session = _claudeSession(cli);
      session.send(const ComposerMessage(text: 'Make and verify the change'));
      await pumpEventQueue();
      _reportTasks(cli, 'todo-1', 'completed', 'in_progress');
      cli.push({'type': 'result', 'subtype': 'error_during_execution'});
      await pumpEventQueue();
      expect(session.taskPlan!.status, TaskPlanStatus.paused);

      session.resumeTask();
      session.resumeTask();
      await pumpEventQueue();
      expect(cli.users, hasLength(2));
      expect(session.taskPlan!.status, isNot(TaskPlanStatus.running));
      expect(session.taskPlan!.steps[0].status, TaskStepStatus.completed);

      _reportTasks(cli, 'todo-2', 'completed', 'in_progress');
      await pumpEventQueue();
      expect(session.taskPlan!.status, TaskPlanStatus.running);
      expect(session.taskPlan!.steps[1].status, TaskStepStatus.running);
    },
  );

  test(
    'an unfinished list stops accruing time when its turn ends normally',
    () async {
      final cli = FakeCli();
      final session = _claudeSession(cli);
      session.send(const ComposerMessage(text: 'Make and verify the change'));
      await pumpEventQueue();
      _reportTasks(cli, 'todo-1', 'in_progress', 'pending');
      cli.push({'type': 'result', 'subtype': 'success'});
      await pumpEventQueue();

      expect(session.taskPlan!.status, TaskPlanStatus.pending);
      expect(session.taskPlan!.steps[0].status, TaskStepStatus.pending);
    },
  );

  test(
    'agent launch instructions request a real task list for multi-step work',
    () {
      expect(ClaudeLaunch.appendedSystemPrompt, contains('TodoWrite'));
      expect(ClaudeLaunch.appendedSystemPrompt, contains('TaskCreate'));
      expect(ClaudeLaunch.appendedSystemPrompt, contains('TaskUpdate'));
    },
  );

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

    expect(session.taskPlan!.status, TaskPlanStatus.paused);
    expect(session.taskPlan!.pauseRequested, isFalse);
    expect(session.taskPlan!.currentStep!.status, TaskStepStatus.paused);
    expect(session.taskPlan!.completedCount, 0);
  });

  test('continue can be retried when the kernel did not open a turn', () {
    final events = StreamController<KernelEvent>.broadcast(sync: true);
    addTearDown(events.close);
    final session = _session(events.stream);
    events.add(const TurnStarted(1, 'turn'));
    events.add(const TodosReported(2, [
      TodoEntry('Work', TodoStatus.inProgress),
    ]));
    events.add(const TurnEnded(3, 'turn', interrupted: true));

    session.resumeTask();

    expect(session.taskPlan!.status, TaskPlanStatus.paused);
    expect(session.taskPlan!.resumeRequested, isFalse);
    expect(session.canResumeTask, isTrue);
  });

  test('an empty todo report leaves ordinary chat without a task plan', () {
    final events = StreamController<KernelEvent>.broadcast(sync: true);
    addTearDown(events.close);
    final session = _session(events.stream);

    events.add(const TodosReported(1, []));

    expect(session.taskPlan, isNull);
  });
}
