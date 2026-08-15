import 'package:flutter_test/flutter_test.dart';
import 'package:recall_app/data/word_catalog.dart';
import 'package:recall_app/models/learning_record.dart';
import 'package:recall_app/review/review_queue.dart';

void main() {
  test(
    'missing catalog word rejects the queue instead of completing a task',
    () {
      final task = ReviewTask(
        id: 1,
        wordId: 'missing',
        word: 'missing',
        reviewDate: DateTime(2026, 8, 13),
        isCompleted: false,
        createdAt: DateTime(2026, 8, 10),
        completedAt: null,
      );
      expect(
        () => ReviewQueueLoader(ListWordCatalog(const [])).load([task]),
        throwsStateError,
      );
    },
  );
}
