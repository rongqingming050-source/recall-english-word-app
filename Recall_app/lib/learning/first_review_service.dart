import '../data/learning_repository.dart';
import '../models/word.dart';
import 'first_review_scheduler.dart';

/// Coordinates first-review calculation without putting business rules in UI
/// code or SQL implementations.
class FirstReviewService {
  const FirstReviewService({
    required this.repository,
    this.scheduler = const FirstReviewScheduler(),
  });

  final LearningRepository repository;
  final FirstReviewScheduler scheduler;

  Future<void> scheduleTargetWords(
    List<Word> targetWords, {
    required DateTime now,
  }) async {
    final records = await Future.wait(
      targetWords.map((word) async {
        final wordId = word.id;
        final record = await repository.getRecord(wordId);
        if (record == null) {
          throw StateError('${word.word} has no learning record.');
        }
        return record;
      }),
    );

    final datesByWordId = <String, DateTime>{
      for (final record in records)
        record.wordId: scheduler.calculateFirstReviewDate(
          record,
          baseDate: now,
        ),
    };

    await repository.scheduleFirstReviews(datesByWordId, now: now);
  }
}
