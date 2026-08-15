class DailyNewWordTask {
  const DailyNewWordTask({
    required this.id,
    required this.taskDate,
    required this.wordId,
    required this.isFirstLayerCompleted,
    required this.isCompleted,
    required this.createdAt,
    required this.firstLayerCompletedAt,
    required this.completedAt,
  });

  final int id;
  final DateTime taskDate;
  final String wordId;
  final bool isFirstLayerCompleted;
  final bool isCompleted;
  final DateTime createdAt;
  final DateTime? firstLayerCompletedAt;
  final DateTime? completedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'taskDate': _dateText(taskDate),
    'wordId': wordId,
    'firstLayerCompleted': isFirstLayerCompleted,
    'completed': isCompleted,
    'createdAt': createdAt.toIso8601String(),
    'firstLayerCompletedAt': firstLayerCompletedAt?.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };
}

class DailyTaskBatch {
  const DailyTaskBatch({
    required this.taskDate,
    required this.targetCount,
    required this.createdAt,
  });

  final DateTime taskDate;
  final int targetCount;
  final DateTime createdAt;
}

String _dateText(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
