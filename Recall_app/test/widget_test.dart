import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recall_app/app.dart';
import 'package:recall_app/data/memory_learning_repository.dart';
import 'package:recall_app/data/vocabulary_repository.dart';
import 'package:recall_app/models/word.dart';
import 'package:recall_app/models/first_layer_word_state.dart';
import 'package:recall_app/models/learning_record.dart';
import 'package:recall_app/pages/debug_learning_data_page.dart';
import 'package:recall_app/pages/study_page.dart';

import 'fixtures/test_words.dart';

final testVocabulary = ListVocabularyRepository(testWords);

void main() {
  test('test word data contains ten complete entries', () {
    expect(testWords, hasLength(10));

    for (final word in testWords) {
      expect(word.word, isNotEmpty);
      expect(word.phonetic, isNotEmpty);
      expect(word.meaning, isNotEmpty);
      expect(word.example, isNotEmpty);
    }
  });

  testWidgets('starts a study round and reveals a word meaning', (
    tester,
  ) async {
    await tester.pumpWidget(RecallApp(vocabulary: testVocabulary));
    await tester.pumpAndSettle();

    expect(find.text('Recall'), findsOneWidget);
    await tester.tap(find.text('开始今日学习'));
    await tester.pumpAndSettle();

    expect(find.text('abandon'), findsOneWidget);
    expect(find.text('放弃；抛弃'), findsNothing);
    expect(find.text('认识'), findsNothing);
    expect(find.text('不确定'), findsNothing);
    expect(find.text('不认识'), findsNothing);

    await tester.tap(find.text('查看释义'));
    await tester.pump();

    expect(find.text('放弃；抛弃'), findsOneWidget);
    expect(find.text('They had to abandon the old plan.'), findsOneWidget);
    expect(find.text('认识'), findsOneWidget);
    expect(find.text('不确定'), findsOneWidget);
    expect(find.text('不认识'), findsOneWidget);
  });

  testWidgets('appearance dots turn green from bottom to top', (tester) async {
    const word = Word(
      word: 'sample',
      phonetic: '/ˈsæmpəl/',
      meaning: '样例',
      example: 'This is a sample.',
    );

    await tester.pumpWidget(const MaterialApp(home: StudyPage(words: [word])));

    expect(find.bySemanticsLabel('已学习 0 次，共 3 次'), findsOneWidget);
    expect(_dotColor(tester, 0), isNot(Colors.green));
    expect(_dotColor(tester, 1), isNot(Colors.green));
    expect(_dotColor(tester, 2), isNot(Colors.green));

    await tester.tap(find.text('查看释义'));
    await tester.pump();
    await tester.tap(find.text('不认识'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('已学习 1 次，共 3 次'), findsOneWidget);
    expect(_dotColor(tester, 0), isNot(Colors.green));
    expect(_dotColor(tester, 1), isNot(Colors.green));
    expect(_dotColor(tester, 2), Colors.green);

    await tester.tap(find.text('查看释义'));
    await tester.pump();
    await tester.tap(find.text('不确定'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('已学习 2 次，共 3 次'), findsOneWidget);
    expect(_dotColor(tester, 0), isNot(Colors.green));
    expect(_dotColor(tester, 1), Colors.green);
    expect(_dotColor(tester, 2), Colors.green);
  });

  testWidgets('context page is not shown before the first layer completes', (
    tester,
  ) async {
    await tester.pumpWidget(RecallApp(vocabulary: testVocabulary));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始今日学习'));
    await tester.pumpAndSettle();

    expect(find.text('语境强化'), findsNothing);
    await tester.tap(find.text('查看释义'));
    await tester.pump();
    expect(find.text('语境强化'), findsNothing);
  });

  testWidgets('first-layer completion opens the reading-only context page', (
    tester,
  ) async {
    final repository = MemoryLearningRepository();
    final now = DateTime.now();
    final expectedReviewDate = DateTime(now.year, now.month, now.day + 3);
    await tester.pumpWidget(
      RecallApp(repository: repository, vocabulary: testVocabulary),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始今日学习'));
    await tester.pumpAndSettle();

    for (var index = 0; index < testWords.length; index++) {
      expect(find.text(testWords[index].word), findsOneWidget);
      await tester.tap(find.text('查看释义'));
      await tester.pump();
      await tester.tap(find.text('认识'));
      await tester.pumpAndSettle();
    }

    expect(find.text('语境强化'), findsOneWidget);
    expect(find.text('阅读完成'), findsOneWidget);
    expect(find.text('认识'), findsNothing);
    expect(find.text('不确定'), findsNothing);
    expect(find.text('不认识'), findsNothing);
    expect(find.text('本轮学习完成'), findsNothing);

    final article = tester.widget<RichText>(
      find.byKey(const ValueKey('context-article')),
    );
    final rootSpan = article.text as TextSpan;
    expect(rootSpan.toPlainText(), contains('A careful reader encountered'));
    expect(rootSpan.style?.fontFamily, 'serif');

    final boldWords = rootSpan.children!
        .cast<TextSpan>()
        .where((span) => span.style?.fontWeight == FontWeight.bold)
        .map((span) => span.text?.toLowerCase())
        .toSet();
    expect(
      boldWords,
      containsAll(testWords.map((word) => word.word.toLowerCase())),
    );

    await tester.tap(find.text('阅读完成'));
    await tester.pumpAndSettle();

    final scheduledTasks = await repository.getAllReviewTasks();
    expect(scheduledTasks, hasLength(testWords.length));
    expect(
      scheduledTasks.map((task) => task.reviewDate),
      everyElement(expectedReviewDate),
    );

    expect(find.text('本轮学习完成'), findsOneWidget);
    expect(find.text('本轮目标单词：10'), findsOneWidget);
    expect(find.text('第一次直接认识：10'), findsOneWidget);
    expect(find.text('第一次不确定：0'), findsOneWidget);
    expect(find.text('第一次不认识：0'), findsOneWidget);
    expect(find.text('经过三次学习：0'), findsOneWidget);
    expect(find.text('高难词：0'), findsOneWidget);

    await tester.tap(find.text('返回首页'));
    await tester.pumpAndSettle();
    expect(find.text('今日任务已完成'), findsOneWidget);
  });

  testWidgets('home counts today and overdue tasks but excludes future tasks', (
    tester,
  ) async {
    final repository = MemoryLearningRepository();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final words = testWords.take(3).toList();
    final states = words
        .map(
          (word) =>
              FirstLayerWordState(word: word)
                ..recordJudgment(StudyChoice.known),
        )
        .toList();
    await repository.saveFirstLayerResults(states, completedAt: now);
    await repository.scheduleFirstReviews({
      stableWordId(words[0].word): today.subtract(const Duration(days: 1)),
      stableWordId(words[1].word): today,
      stableWordId(words[2].word): today.add(const Duration(days: 1)),
    }, now: now);

    await tester.pumpWidget(
      RecallApp(repository: repository, vocabulary: testVocabulary),
    );
    await tester.pumpAndSettle();

    expect(find.text('待复习：2'), findsOneWidget);
  });

  testWidgets('tapping a bold context word can schedule tomorrow review', (
    tester,
  ) async {
    final repository = MemoryLearningRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: StudyPage(
          words: [testWords.first],
          repository: repository,
          now: () => DateTime(2026, 8, 13),
        ),
      ),
    );

    await tester.tap(find.text('查看释义'));
    await tester.pump();
    await tester.tap(find.text('认识'));
    await tester.pumpAndSettle();

    final richText = tester.widget<RichText>(
      find.byKey(const ValueKey('context-article')),
    );
    final rootSpan = richText.text as TextSpan;
    final wordSpan = rootSpan.children!.cast<TextSpan>().firstWhere(
      (span) => span.text?.toLowerCase() == 'abandon',
    );
    (wordSpan.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pumpAndSettle();

    expect(find.text('abandon'), findsOneWidget);
    expect(find.text('/əˈbændən/'), findsOneWidget);
    expect(find.text('放弃；抛弃'), findsOneWidget);
    expect(find.text('They had to abandon the old plan.'), findsOneWidget);
    expect(find.text('重学'), findsOneWidget);

    await tester.tap(find.text('重学'));
    await tester.pump();

    expect(find.text('已安排明天复习'), findsOneWidget);
    final tasks = await repository.getAllReviewTasks();
    expect(tasks, hasLength(1));
    expect(tasks.single.word, 'abandon');
    expect(tasks.single.reviewDate, DateTime(2026, 8, 14));
  });

  testWidgets('debug page lists records and opens complete read-only details', (
    tester,
  ) async {
    final repository = MemoryLearningRepository();
    final state = FirstLayerWordState(word: testWords.first)
      ..recordJudgment(StudyChoice.unknown)
      ..recordJudgment(StudyChoice.unsure)
      ..recordJudgment(StudyChoice.unknown);
    await repository.saveFirstLayerResults([
      state,
    ], completedAt: DateTime(2026, 8, 13));
    await repository.overrideReviewTaskToTomorrow(
      testWords.first,
      now: DateTime(2026, 8, 13),
    );

    await tester.pumpWidget(
      MaterialApp(home: DebugLearningDataPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('abandon'), findsOneWidget);
    expect(find.textContaining('不认识 / 不确定 / 不认识'), findsOneWidget);
    expect(find.text('高难词'), findsOneWidget);
    expect(find.byTooltip('刷新'), findsOneWidget);
    expect(find.byTooltip('导出 JSON'), findsOneWidget);

    await tester.tap(find.text('abandon'));
    await tester.pumpAndSettle();

    expect(find.text('当前学习阶段'), findsOneWidget);
    expect(find.text('第一层第一次结果'), findsOneWidget);
    expect(find.text('第一层第二次结果'), findsOneWidget);
    expect(find.text('第一层第三次结果'), findsOneWidget);
    for (final label in [
      '是否高难词',
      '上次复习时间',
      '下次复习时间',
      '当前复习任务日期',
      '当前复习间隔',
      '复习次数',
      '遗忘次数',
      '最近反应时间',
      '平均反应时间',
    ]) {
      await tester.scrollUntilVisible(find.text(label), 200);
      expect(find.text(label), findsOneWidget);
    }
  });
}

Color? _dotColor(WidgetTester tester, int index) {
  final container = tester.widget<Container>(
    find.byKey(ValueKey('appearance-dot-$index')),
  );
  final decoration = container.decoration! as BoxDecoration;
  return decoration.color;
}
