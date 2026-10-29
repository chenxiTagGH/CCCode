import 'dart:async';

import 'package:flutter/material.dart';

import 'task_plan.dart';
import 'task_plan_controller.dart';
import 'task_plan_panel.dart';

/// A temporary visual harness for checking the task-plan panel in a real app.
class TaskPlanDemoScreen extends StatefulWidget {
  const TaskPlanDemoScreen({super.key});

  @override
  State<TaskPlanDemoScreen> createState() => _TaskPlanDemoScreenState();
}

class _TaskPlanDemoScreenState extends State<TaskPlanDemoScreen> {
  static const _steps = [
    ('check-entry', '检查任务入口'),
    ('open-drawer', '打开右侧抽屉'),
    ('complete-flow', '完成任务流程'),
  ];

  late final TaskPlanController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = TaskPlanController();
    _reset();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _advance());
  }

  void _reset() {
    _controller.create(
      title: 'Task plan demo',
      steps: [
        for (final (id, title) in _steps)
          TaskStep(
            id: id,
            title: title,
            estimateMin: const Duration(seconds: 2),
            estimateMax: const Duration(seconds: 5),
          ),
      ],
    );
  }

  void _advance() {
    final plan = _controller.value;
    if (plan == null || plan.status == TaskPlanStatus.completed) return;
    if (plan.status == TaskPlanStatus.pending) {
      _controller.start();
      return;
    }
    if (plan.status == TaskPlanStatus.running) {
      _controller.completeStep();
      if (_controller.value?.status == TaskPlanStatus.pending) {
        _controller.start();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TaskPlanPanel(
      controller: _controller,
      onPause: () => _controller.pause(),
      onResume: _controller.resume,
      onRetry: _controller.retryFailed,
      onStop: _controller.cancel,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Task plan demo'),
          actions: [
            IconButton(
              tooltip: 'Advance task',
              onPressed: _advance,
              icon: const Icon(Icons.skip_next),
            ),
            IconButton(
              tooltip: 'Reset demo',
              onPressed: () {
                _controller.clear();
                _reset();
              },
              icon: const Icon(Icons.restart_alt),
            ),
          ],
        ),
        body: Center(
          child: ValueListenableBuilder<TaskPlan?>(
            valueListenable: _controller,
            builder: (context, plan, _) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.task_alt, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'This is an isolated visual demo.\n'
                  'The task plan advances every two seconds.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  plan == null
                      ? 'No task plan'
                      : '${plan.completedCount}/${plan.steps.length} completed',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _advance,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Advance task'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
