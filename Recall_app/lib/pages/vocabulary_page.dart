import 'package:flutter/material.dart';

import '../data/vocabulary_repository.dart';
import '../learning/daily_task_service.dart';

class VocabularyPage extends StatelessWidget {
  const VocabularyPage({
    super.key,
    required this.vocabulary,
    required this.dailyTaskService,
  });

  final VocabularyRepository vocabulary;
  final DailyTaskService dailyTaskService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('词库信息')),
      body: FutureBuilder<VocabularyProgress>(
        future: dailyTaskService.getVocabularyProgress(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('词库进度读取失败：${snapshot.error}'));
          }
          final progress = snapshot.requireData;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                vocabulary.book.name,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              _ProgressRow(label: '总词数', value: progress.totalCount),
              _ProgressRow(label: '已进入学习', value: progress.lifecycleCount),
              _ProgressRow(label: '未学习', value: progress.unlearnedCount),
              _ProgressRow(
                label: '第一层完成',
                value: progress.firstLayerCompletedCount,
              ),
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: progress.totalCount == 0
                    ? 0
                    : progress.lifecycleCount / progress.totalCount,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    trailing: Text('$value'),
  );
}
