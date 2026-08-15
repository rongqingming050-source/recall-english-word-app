import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recall_app/data/memory_learning_repository.dart';
import 'package:recall_app/pages/new_word_settings_page.dart';

void main() {
  testWidgets('preset saves and updates the selected value without errors', (
    tester,
  ) async {
    final repository = MemoryLearningRepository();

    await tester.pumpWidget(
      MaterialApp(home: NewWordSettingsPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('20 个'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(await repository.getDailyNewWordTarget(), 20);
    expect(find.text('每日新词设置已保存'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(find.text('新数量从今天开始生效'), findsOneWidget);
  });

  testWidgets('custom value saves after the dialog closes without errors', (
    tester,
  ) async {
    final repository = MemoryLearningRepository();

    await tester.pumpWidget(
      MaterialApp(home: NewWordSettingsPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '25');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(await repository.getDailyNewWordTarget(), 25);
    expect(find.text('25 个'), findsOneWidget);
    expect(find.text('每日新词设置已保存'), findsOneWidget);
  });

  testWidgets('invalid custom value stays in the dialog and is not saved', (
    tester,
  ) async {
    final repository = MemoryLearningRepository();

    await tester.pumpWidget(
      MaterialApp(home: NewWordSettingsPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '201');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('自定义每日新词'), findsOneWidget);
    expect(find.text('请输入 1～200 之间的整数'), findsOneWidget);
    expect(await repository.getDailyNewWordTarget(), 10);
  });
}
