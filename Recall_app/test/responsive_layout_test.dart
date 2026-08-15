import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recall_app/app.dart';
import 'package:recall_app/data/memory_learning_repository.dart';
import 'package:recall_app/data/vocabulary_repository.dart';
import 'package:recall_app/models/word.dart';
import 'package:recall_app/pages/study_page.dart';

void main() {
  final vocabulary = ListVocabularyRepository(_words(10));

  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    testWidgets('home has no overflow at ${size.width}x${size.height}', (
      tester,
    ) async {
      await _setSurface(tester, size);
      await tester.pumpWidget(RecallApp(vocabulary: vocabulary));
      await tester.pumpAndSettle();

      final exception = tester.takeException();
      if (exception case final FlutterError error) {
        fail(error.toStringDeep());
      }
      expect(exception, isNull);
      expect(find.text('开始学习'), findsOneWidget);
    });
  }

  testWidgets('home supports large system text without overflow', (
    tester,
  ) async {
    await _setSurface(tester, const Size(360, 640), textScaleFactor: 2);
    await tester.pumpWidget(RecallApp(vocabulary: vocabulary));
    await tester.pumpAndSettle();

    final mediaScales = tester
        .widgetList<MediaQuery>(find.byType(MediaQuery))
        .map((widget) => widget.data.textScaler.scale(1))
        .toList();
    expect(mediaScales, contains(2.0));
    final exception = tester.takeException();
    if (exception case final FlutterError error) {
      fail(error.toStringDeep());
    }
    expect(exception, isNull);
  });

  testWidgets('study answer controls support large system text', (
    tester,
  ) async {
    await _setSurface(tester, const Size(360, 800), textScaleFactor: 2);
    await tester.pumpWidget(
      MaterialApp(
        home: StudyPage(
          words: [_words(1).single],
          repository: MemoryLearningRepository(),
        ),
      ),
    );
    await tester.tap(find.text('查看释义'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('认识'), findsOneWidget);
    expect(find.text('不确定'), findsOneWidget);
    expect(find.text('不认识'), findsOneWidget);
  });
}

Future<void> _setSurface(
  WidgetTester tester,
  Size size, {
  double textScaleFactor = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

List<Word> _words(int count) => List.generate(
  count,
  (index) => Word(
    word: 'responsive$index',
    phonetic: '/r$index/',
    meaning: '响应式测试词义$index',
    example: 'Responsive example number $index.',
  ),
);
