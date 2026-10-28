import 'package:baocode/tasks/task_plan.dart';
import 'package:baocode/tasks/task_plan_store.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _FailingStore implements PreferenceStore {
  @override
  Future<Map<String, Object?>> read() async => <String, Object?>{};

  @override
  Future<void> write(Map<String, Object?> preferences) async {
    throw StateError('disk unavailable');
  }
}

void main() {
  TaskPlan plan() => TaskPlan(
    title: 'Ship',
    steps: const [TaskStep(id: 'one', title: 'Build')],
  );

  test('persists plans under taskPlans and restores them', () async {
    final preferences = MemoryPreferenceStore();
    final store = TaskPlanStore(preferences);
    await store.write('agent-1', plan());
    final restored = await store.read('agent-1');

    expect(restored!.title, 'Ship');
    expect(restored.steps.single.title, 'Build');
    expect(preferences.preferences['taskPlans'], isA<Map>());
  });

  test('serializes writes in call order', () async {
    final preferences = MemoryPreferenceStore();
    final store = TaskPlanStore(preferences);
    await Future.wait([
      store.write('agent-1', plan()),
      store.write(
        'agent-1',
        plan().copyWith(title: 'Newer'),
      ),
    ]);

    expect((await store.read('agent-1'))!.title, 'Newer');
  });

  test('a persistence failure is best effort', () async {
    final store = TaskPlanStore(_FailingStore());
    await expectLater(store.write('agent-1', plan()), completes);
    await expectLater(store.read('agent-1'), completion(equals(null)));
  });

  test('removing a plan deletes only its key', () async {
    final preferences = MemoryPreferenceStore();
    final store = TaskPlanStore(preferences);
    await store.write('one', plan());
    await store.write('two', plan());
    await store.write('one', null);

    expect(await store.read('one'), isNull);
    expect(await store.read('two'), isNotNull);
  });
}
