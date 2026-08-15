import '../data/word_catalog.dart';
import '../models/learning_record.dart';
import '../models/word.dart';

class ReviewQueueItem {
  const ReviewQueueItem({required this.task, required this.word});

  final ReviewTask task;
  final Word word;
}

class ReviewQueueLoader {
  const ReviewQueueLoader(this.catalog);

  final WordCatalog catalog;

  List<ReviewQueueItem> load(List<ReviewTask> tasks) {
    return tasks
        .map((task) {
          final word = catalog.findById(task.wordId);
          if (word == null) {
            throw StateError('找不到复习任务对应的单词：${task.wordId}');
          }
          return ReviewQueueItem(task: task, word: word);
        })
        .toList(growable: false);
  }
}
