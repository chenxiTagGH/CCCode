enum TaskPlanStatus { pending, running, completed, failed, paused, cancelled }

enum TaskStepStatus { pending, running, completed, failed, paused, cancelled }

const _unchanged = Object();

class TaskStep {
  const TaskStep({
    required this.id,
    required this.title,
    this.description,
    this.estimateMin,
    this.estimateMax,
    this.status = TaskStepStatus.pending,
    this.startedAt,
    this.finishedAt,
    this.runningSince,
    this.elapsed = Duration.zero,
    this.error,
  });

  final String id;
  final String title;
  final String? description;
  final Duration? estimateMin;
  final Duration? estimateMax;
  final TaskStepStatus status;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime? runningSince;
  final Duration elapsed;
  final String? error;

  Duration elapsedAt(DateTime now) {
    final since = runningSince;
    if (status != TaskStepStatus.running || since == null) return elapsed;
    final difference = now.difference(since);
    return elapsed + (difference.isNegative ? Duration.zero : difference);
  }

  TaskStep copyWith({
    String? title,
    String? description,
    Duration? estimateMin,
    Duration? estimateMax,
    TaskStepStatus? status,
    Object? startedAt = _unchanged,
    Object? finishedAt = _unchanged,
    Object? runningSince = _unchanged,
    Duration? elapsed,
    Object? error = _unchanged,
  }) => TaskStep(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    estimateMin: estimateMin ?? this.estimateMin,
    estimateMax: estimateMax ?? this.estimateMax,
    status: status ?? this.status,
    startedAt: identical(startedAt, _unchanged)
        ? this.startedAt
        : startedAt as DateTime?,
    finishedAt: identical(finishedAt, _unchanged)
        ? this.finishedAt
        : finishedAt as DateTime?,
    runningSince: identical(runningSince, _unchanged)
        ? this.runningSince
        : runningSince as DateTime?,
    elapsed: elapsed ?? this.elapsed,
    error: identical(error, _unchanged) ? this.error : error as String?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    if (description != null) 'description': description,
    if (estimateMin != null) 'estimateMinMs': estimateMin!.inMilliseconds,
    if (estimateMax != null) 'estimateMaxMs': estimateMax!.inMilliseconds,
    'status': status.name,
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
    if (runningSince != null) 'runningSince': runningSince!.toIso8601String(),
    'elapsedMs': elapsed.inMilliseconds,
    if (error != null) 'error': error,
  };

  static TaskStep? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _text(json['id']);
    final title = _text(json['title']);
    if (id == null || title == null) return null;
    return TaskStep(
      id: id,
      title: title,
      description: _text(json['description']),
      estimateMin: _duration(json['estimateMinMs']),
      estimateMax: _duration(json['estimateMaxMs']),
      status: _enumValue(TaskStepStatus.values, json['status']) ??
          TaskStepStatus.pending,
      startedAt: _date(json['startedAt']),
      finishedAt: _date(json['finishedAt']),
      runningSince: _date(json['runningSince']),
      elapsed: _duration(json['elapsedMs']) ?? Duration.zero,
      error: _text(json['error']),
    );
  }
}

class TaskPlan {
  TaskPlan({
    required this.title,
    required List<TaskStep> steps,
    this.status = TaskPlanStatus.pending,
    this.startedAt,
    this.finishedAt,
    this.pauseRequested = false,
  }) : steps = List.unmodifiable(steps);

  final String title;
  final List<TaskStep> steps;
  final TaskPlanStatus status;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final bool pauseRequested;

  TaskStep? get currentStep =>
      steps.where((step) => step.status == TaskStepStatus.running).firstOrNull ??
      steps.where((step) => step.status == TaskStepStatus.failed).firstOrNull ??
      steps.where((step) => step.status == TaskStepStatus.paused).firstOrNull ??
      steps.where((step) => step.status == TaskStepStatus.pending).firstOrNull;

  int get completedCount =>
      steps.where((step) => step.status == TaskStepStatus.completed).length;

  Duration get elapsed => steps.fold(Duration.zero, (sum, step) => sum + step.elapsed);

  Duration elapsedAt(DateTime now) =>
      steps.fold(Duration.zero, (sum, step) => sum + step.elapsedAt(now));

  TaskPlan copyWith({
    String? title,
    List<TaskStep>? steps,
    TaskPlanStatus? status,
    Object? startedAt = _unchanged,
    Object? finishedAt = _unchanged,
    bool? pauseRequested,
  }) => TaskPlan(
    title: title ?? this.title,
    steps: steps ?? this.steps,
    status: status ?? this.status,
    startedAt: identical(startedAt, _unchanged)
        ? this.startedAt
        : startedAt as DateTime?,
    finishedAt: identical(finishedAt, _unchanged)
        ? this.finishedAt
        : finishedAt as DateTime?,
    pauseRequested: pauseRequested ?? this.pauseRequested,
  );

  Map<String, Object?> toJson({DateTime? at}) => {
    'version': 1,
    'title': title,
    'status': status.name,
    'steps': [for (final step in steps) step.toJson()],
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
    'pauseRequested': pauseRequested,
    'savedAt': (at ?? DateTime.now()).toIso8601String(),
  };

  static TaskPlan? fromJson(Object? json, {bool recoverRunning = false}) {
    if (json is! Map || json['version'] != 1) return null;
    final title = _text(json['title']);
    final rawSteps = json['steps'];
    if (title == null || rawSteps is! List || rawSteps.isEmpty) return null;
    final steps = <TaskStep>[];
    final ids = <String>{};
    final savedAt = _date(json['savedAt']);
    for (final raw in rawSteps) {
      var step = TaskStep.fromJson(raw);
      if (step == null || !ids.add(step.id)) return null;
      if (recoverRunning && step.status == TaskStepStatus.running) {
        step = step.copyWith(
          status: TaskStepStatus.paused,
          elapsed: savedAt == null ? step.elapsed : step.elapsedAt(savedAt),
          runningSince: null,
        );
      }
      steps.add(step);
    }
    final status = _enumValue(TaskPlanStatus.values, json['status']) ??
        TaskPlanStatus.pending;
    return TaskPlan(
      title: title,
      steps: steps,
      status: recoverRunning && status == TaskPlanStatus.running
          ? TaskPlanStatus.paused
          : status,
      startedAt: _date(json['startedAt']),
      finishedAt: _date(json['finishedAt']),
      pauseRequested: !recoverRunning && json['pauseRequested'] == true,
    );
  }
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value) : null;

Duration? _duration(Object? value) =>
    value is int && value >= 0 ? Duration(milliseconds: value) : null;

T? _enumValue<T extends Enum>(List<T> values, Object? name) =>
    values.where((value) => value.name == name).firstOrNull;
