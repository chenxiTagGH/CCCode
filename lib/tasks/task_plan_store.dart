import '../workspace/preference_store.dart';
import 'task_plan.dart';

/// Serializes reads and writes so a slower save cannot replace a newer one.
/// Share this instance when multiple sessions use the same preference file.
class TaskPlanStore {
  TaskPlanStore(this.preferences);

  final PreferenceStore preferences;
  Future<void> _pending = Future<void>.value();

  Future<TaskPlan?> read(String key) {
    TaskPlan? result;
    final operation = _pending.then((_) async {
      try {
        final state = await preferences.read();
        final plans = state['taskPlans'];
        if (plans is Map) {
          result = TaskPlan.fromJson(plans[key], recoverRunning: true);
        }
      } catch (_) {
        // A damaged or inaccessible file must not block the conversation.
      }
    });
    _pending = operation;
    return operation.then((_) => result);
  }

  Future<void> write(String key, TaskPlan? plan, {DateTime? at}) {
    final snapshot = plan?.toJson(at: at);
    final operation = _pending.then((_) async {
      try {
        final state = Map<String, Object?>.of(await preferences.read());
        final previous = state['taskPlans'];
        final plans = <String, Object?>{
          if (previous is Map)
            for (final entry in previous.entries)
              if (entry.key is String) entry.key as String: entry.value,
        };
        if (snapshot == null) {
          plans.remove(key);
        } else {
          plans[key] = snapshot;
        }
        state['taskPlans'] = plans;
        await preferences.write(state);
      } catch (_) {
        // Persistence is best effort; later saves still get a chance.
      }
    });
    _pending = operation;
    return operation;
  }

  Future<void> flush() => _pending;
}
