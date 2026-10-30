import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/tasks/task_plan.dart';
import 'package:baocode/tasks/task_plan_controller.dart';
import 'package:baocode/tasks/task_plan_drawer.dart';
import 'package:baocode/tasks/task_plan_indicator.dart';
import 'package:baocode/tasks/task_plan_panel.dart';

void main() {
  TaskPlan plan({TaskPlanStatus status = TaskPlanStatus.running}) => TaskPlan(
        title: 'Prepare release',
        status: status,
        steps: [
          const TaskStep(id: 'one', title: 'Build', status: TaskStepStatus.completed),
          const TaskStep(id: 'two', title: 'Verify', status: TaskStepStatus.running),
          const TaskStep(
            id: 'three',
            title: 'Publish',
            estimateMin: Duration(seconds: 30),
            estimateMax: Duration(minutes: 1),
          ),
        ],
      );

  Widget app(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  testWidgets('indicator exposes status and completion count', (tester) async {
    await tester.pumpWidget(app(TaskPlanIndicator(plan: plan(), onTap: () {})));
    expect(find.text('In progress · 1/3'), findsOneWidget);
    expect(find.bySemanticsLabel('In progress, 1/3'), findsOneWidget);
  });

  testWidgets('drawer shows estimates and controls', (tester) async {
    await tester.pumpWidget(app(TaskPlanDrawer(plan: plan(), onClose: () {})));
    expect(find.text('Prepare release'), findsOneWidget);
    expect(find.text('Estimated 30s–1m'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
  });

  testWidgets('panel auto opens and can be closed', (tester) async {
    final controller = TaskPlanController()..value = plan();
    await tester.pumpWidget(app(TaskPlanPanel(controller: controller, child: const SizedBox())));
    await tester.pump();
    expect(find.text('Prepare release'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(find.text('Prepare release'), findsNothing);
    controller.dispose();
  });

  testWidgets('panel drawer stays compact at the top right', (tester) async {
    final controller = TaskPlanController()..value = plan();
    await tester.pumpWidget(
      app(
        SizedBox(
          width: 1200,
          height: 800,
          child: TaskPlanPanel(controller: controller, child: const SizedBox()),
        ),
      ),
    );
    await tester.pump();

    final drawer = find.byType(TaskPlanDrawer);
    expect(tester.getTopLeft(drawer).dx, greaterThan(800));
    expect(tester.getTopLeft(drawer).dy, closeTo(12, 1));
    expect(tester.getSize(drawer).width, lessThan(400));
    expect(tester.getSize(drawer).height, lessThan(500));
    controller.dispose();
  });

  testWidgets('drawer stays open while the task runs', (tester) async {
    final controller = TaskPlanController()..value = plan();
    await tester.pumpWidget(app(TaskPlanPanel(controller: controller, child: const SizedBox())));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Prepare release'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('failed plan keeps drawer visible', (tester) async {
    final controller = TaskPlanController()..value = plan(status: TaskPlanStatus.failed);
    await tester.pumpWidget(app(TaskPlanPanel(controller: controller, child: const SizedBox())));
    await tester.pump();
    expect(find.text('Prepare release'), findsOneWidget);
    controller.dispose();
  });
}
