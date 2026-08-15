import 'package:flutter_test/flutter_test.dart';
import 'package:recall_app/app.dart';
import 'package:recall_app/data/memory_learning_repository.dart';
import 'package:recall_app/data/vocabulary_repository.dart';
import 'package:recall_app/models/word.dart';

void main() {
  testWidgets('home does not count unavailable words as completed', (
    tester,
  ) async {
    final repository = MemoryLearningRepository();
    await repository.setDailyNewWordTarget(30);
    final vocabulary = ListVocabularyRepository(
      List.generate(
        2,
        (index) => Word(
          word: 'remaining$index',
          phonetic: '/r$index/',
          meaning: '剩余$index',
          example: 'Remaining word $index.',
        ),
      ),
    );

    await tester.pumpWidget(
      RecallApp(repository: repository, vocabulary: vocabulary),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('新词：28/30'),
      findsNothing,
      reason: '未分配到的 28 个单词不能被算作今天已完成。',
    );
    expect(find.text('新词：0/2'), findsOneWidget);
  });
}
