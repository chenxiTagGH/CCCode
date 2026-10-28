import 'dart:async';

import 'package:flutter/material.dart';

import 'task_plan.dart';
import 'task_plan_controller.dart';
import 'task_plan_drawer.dart';
import 'task_plan_indicator.dart';

class TaskPlanPanel extends StatefulWidget {
  const TaskPlanPanel({
    super.key,
    required this.controller,
    required this.child,
    this.onPause,
    this.onResume,
    this.onRetry,
    this.onStop,
  });

  final TaskPlanController controller;
  final Widget child;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onRetry;
  final VoidCallback? onStop;

  @override
  State<TaskPlanPanel> createState() => _TaskPlanPanelState();
}

class _TaskPlanPanelState extends State<TaskPlanPanel> {
  Timer? _clock;
  bool _drawerOpen = false;
  bool _autoRevealPending = false;
  int _lastPlanHash = 0;
  TaskPlanStatus? _lastStatus;
  int _revealGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(covariant TaskPlanPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _changed();
    }
  }

  void _changed() {
    final plan = widget.controller.value;
    if (plan == null) {
      _lastStatus = null;
      _lastPlanHash = 0;
      _revealGeneration++;
      _clock?.cancel();
      _clock = null;
      if (mounted) setState(() => _drawerOpen = false);
      return;
    }
    final hash = Object.hash(
      plan.title,
      Object.hashAll(plan.steps.map((step) => Object.hash(step.id, step.title))),
    );
    final isNewPlan = hash != _lastPlanHash;
    final failedNow = plan.status == TaskPlanStatus.failed;
    final justFailed = failedNow && _lastStatus != TaskPlanStatus.failed;
    _lastStatus = plan.status;
    if (isNewPlan || justFailed) {
      _lastPlanHash = hash;
      if (mounted) {
        final generation = ++_revealGeneration;
        setState(() {
          _drawerOpen = true;
          _autoRevealPending = !failedNow;
        });
        if (_autoRevealPending) {
          Future<void>.delayed(const Duration(milliseconds: 1500), () {
            if (mounted &&
                generation == _revealGeneration &&
                _autoRevealPending &&
                widget.controller.value == plan) {
              setState(() {
                _drawerOpen = false;
                _autoRevealPending = false;
              });
            }
          });
        }
      }
    }
    final ticking = _drawerOpen && plan.status == TaskPlanStatus.running;
    if (ticking && _clock == null) {
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!ticking) {
      _clock?.cancel();
      _clock = null;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _clock?.cancel();
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        ValueListenableBuilder(
          valueListenable: widget.controller,
          builder: (context, plan, _) {
            if (plan == null) return const SizedBox.shrink();
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  top: 10,
                  right: 12,
                  child: TaskPlanIndicator(plan: plan, onTap: () => setState(() => _drawerOpen = true)),
                ),
                if (_drawerOpen)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TaskPlanDrawer(
                        plan: plan,
                        onClose: () => setState(() {
                          _drawerOpen = false;
                          _autoRevealPending = false;
                        }),
                        onPause: widget.onPause,
                        onResume: widget.onResume,
                        onRetry: widget.onRetry,
                        onStop: widget.onStop,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
