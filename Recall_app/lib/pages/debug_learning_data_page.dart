import 'package:flutter/material.dart';

import '../data/learning_data_exporter.dart';
import '../data/learning_repository.dart';
import '../data/vocabulary_repository.dart';
import '../learning/daily_task_service.dart';
import '../models/daily_new_word_task.dart';
import '../models/first_layer_word_state.dart';
import '../models/learning_record.dart';
import '../models/context_article.dart';
import '../review/review_scheduler.dart';

class DebugLearningDataPage extends StatefulWidget {
  const DebugLearningDataPage({
    super.key,
    required this.repository,
    this.vocabulary,
    this.dailyTaskService,
    this.exporter = const LearningDataExporter(),
  });

  final LearningRepository repository;
  final VocabularyRepository? vocabulary;
  final DailyTaskService? dailyTaskService;
  final LearningDataExporter exporter;

  @override
  State<DebugLearningDataPage> createState() => _DebugLearningDataPageState();
}

class _DebugLearningDataPageState extends State<DebugLearningDataPage> {
  late Future<_DebugData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _dataFuture = _loadData();
    });
  }

  Future<_DebugData> _loadData() async {
    final results = await Future.wait([
      widget.repository.getAllRecords(),
      widget.repository.getAllReviewTasks(),
      widget.repository.getAllReviewAttempts(),
      widget.repository.getAllDailyNewWordTasks(),
      widget.repository.getDailyNewWordTarget(),
      widget.repository.getAllContextArticles(),
    ]);
    final progress = await widget.dailyTaskService?.getVocabularyProgress();
    return _DebugData(
      records: results[0] as List<LearningRecord>,
      tasks: results[1] as List<ReviewTask>,
      attempts: results[2] as List<ReviewAttempt>,
      dailyTasks: results[3] as List<DailyNewWordTask>,
      dailyTarget: results[4] as int,
      contextArticles: results[5] as List<ContextArticle>,
      progress: progress,
      currentDate: widget.dailyTaskService?.now(),
    );
  }

  Future<void> _export() async {
    try {
      final file = await widget.exporter.export(
        widget.repository,
        vocabulary: widget.vocabulary,
        dailyTaskService: widget.dailyTaskService,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('JSON 已导出：${file.path}')));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('学习数据（调试）'),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: _export,
            tooltip: '导出 JSON',
            icon: const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      body: FutureBuilder<_DebugData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('读取失败：${snapshot.error}'));
          }

          final data = snapshot.data ?? const _DebugData();
          final records = data.records;

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (widget.dailyTaskService != null)
                  _DailyTaskDebugSummary(data: data),
                _ContextArticleDebugSummary(articles: data.contextArticles),
                if (records.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('暂无本地学习记录')),
                  ),
                for (final record in records)
                  ListTile(
                    title: Text(record.word),
                    subtitle: Text(
                      '${_stageLabel(record.stage)} · '
                      '${_choiceLabel(record.firstResult)} / '
                      '${_choiceLabel(record.secondResult)} / '
                      '${_choiceLabel(record.thirdResult)}',
                    ),
                    trailing: record.isDifficult
                        ? const Chip(label: Text('高难词'))
                        : null,
                    onTap: () {
                      final tasks = data.tasks
                          .where((task) => task.wordId == record.wordId)
                          .toList();
                      final attempts = data.attempts
                          .where((attempt) => attempt.wordId == record.wordId)
                          .toList();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DebugLearningRecordDetailPage(
                            record: record,
                            reviewTasks: tasks,
                            reviewAttempts: attempts,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DailyTaskDebugSummary extends StatelessWidget {
  const _DailyTaskDebugSummary({required this.data});

  final _DebugData data;

  @override
  Widget build(BuildContext context) {
    final progress = data.progress;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '每日任务数据（只读）',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('当前日期：${_dateTimeLabel(data.currentDate)}'),
            Text('每日新词目标：${data.dailyTarget}'),
            Text('词库总数：${progress?.totalCount ?? 0}'),
            Text('已进入学习：${progress?.lifecycleCount ?? 0}'),
            Text('未学习：${progress?.unlearnedCount ?? 0}'),
            const SizedBox(height: 8),
            Text(
              data.dailyTasks.isEmpty
                  ? '每日任务：空'
                  : data.dailyTasks
                        .map(
                          (task) =>
                              '${task.taskDate.toIso8601String().substring(0, 10)} · '
                              '${task.wordId} · '
                              '第一层 ${task.isFirstLayerCompleted ? '完成' : '未完成'} · '
                              '${task.isCompleted ? '完成' : '待完成'}',
                        )
                        .join('\n'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContextArticleDebugSummary extends StatelessWidget {
  const _ContextArticleDebugSummary({required this.articles});

  final List<ContextArticle> articles;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI 语境文章（只读）',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (articles.isEmpty)
              const Text('暂无记录')
            else
              for (final article in articles.reversed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'contextSessionId: ${article.contextSessionId}\n'
                    'status: ${article.status.name}\n'
                    'title: ${article.title.isEmpty ? '空' : article.title}\n'
                    'sourceWordIds: ${article.sourceWordIds.join(', ')}\n'
                    'usedWordIds: ${article.usedWordIds.join(', ')}\n'
                    'provider: ${article.provider.isEmpty ? '空' : article.provider}\n'
                    'model: ${article.model.isEmpty ? '空' : article.model}\n'
                    'promptVersion: ${article.promptVersion.isEmpty ? '空' : article.promptVersion}\n'
                    'generatedAt: ${article.generatedAt.toIso8601String()}\n'
                    'errorCode: ${article.errorCode ?? '空'}',
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class DebugLearningRecordDetailPage extends StatelessWidget {
  const DebugLearningRecordDetailPage({
    super.key,
    required this.record,
    this.reviewTasks = const [],
    this.reviewAttempts = const [],
  });

  final LearningRecord record;
  final List<ReviewTask> reviewTasks;
  final List<ReviewAttempt> reviewAttempts;

  @override
  Widget build(BuildContext context) {
    final currentTask = reviewTasks
        .where((task) => !task.isCompleted)
        .firstOrNull;
    final latestAttempt = reviewAttempts.lastOrNull;
    final rows = <(String, String)>[
      ('单词 ID', record.wordId),
      ('单词', record.word),
      ('当前学习阶段', _stageLabel(record.stage)),
      ('第一层第一次结果', _choiceLabel(record.firstResult)),
      ('第一层第二次结果', _choiceLabel(record.secondResult)),
      ('第一层第三次结果', _choiceLabel(record.thirdResult)),
      ('是否高难词', record.isDifficult ? '是' : '否'),
      ('第一层完成时间', _dateTimeLabel(record.firstLayerCompletedAt)),
      ('是否等待复习', record.isWaitingReview ? '是' : '否'),
      ('上次复习时间', _dateTimeLabel(record.lastReviewDate)),
      ('上次复习结果', _choiceLabel(record.lastReviewResult)),
      ('下次复习时间', _dateTimeLabel(record.nextReviewDate)),
      ('当前复习任务日期', _dateTimeLabel(currentTask?.reviewDate)),
      ('当前复习间隔', _nullableNumber(record.reviewIntervalDays, '天')),
      ('复习次数', '${record.reviewCount}'),
      ('遗忘次数', '${record.forgetCount}'),
      ('最近反应时间', _nullableNumber(record.recentReactionMilliseconds, '毫秒')),
      ('平均反应时间', _nullableNumber(record.averageReactionMilliseconds, '毫秒')),
      ('最近熟练程度', _fluencyLabel(latestAttempt?.fluency)),
      (
        '复习任务历史',
        reviewTasks.isEmpty
            ? '空'
            : reviewTasks.reversed
                  .map(
                    (task) =>
                        '#${task.id} · ${task.reviewDate.toIso8601String()} · '
                        '${task.isCompleted ? '已完成' : '未完成'} · '
                        '完成于 ${_dateTimeLabel(task.completedAt)}',
                  )
                  .join('\n'),
      ),
      (
        '复习行为历史',
        reviewAttempts.isEmpty
            ? '空'
            : reviewAttempts.reversed
                  .map(
                    (attempt) =>
                        '#${attempt.id} · 任务 ${attempt.reviewTaskId} · '
                        '${_choiceLabel(attempt.result)} · ${attempt.reactionMilliseconds} 毫秒 · '
                        '${_fluencyLabel(attempt.fluency)} · '
                        '旧间隔 ${_nullableNumber(attempt.previousIntervalDays, '天')} · '
                        '实际间隔 ${_nullableNumber(attempt.actualElapsedDays, '天')} · '
                        '新间隔 ${_nullableNumber(attempt.nextIntervalDays, '天')} · '
                        '原计划 ${_dateTimeLabel(attempt.scheduledReviewDate)} · '
                        '实际 ${_dateTimeLabel(attempt.actualReviewDate)} · '
                        '逾期 ${_nullableNumber(attempt.overdueDays, '天')} · '
                        '下次 ${_dateTimeLabel(attempt.nextReviewDate)} · '
                        '算法 ${attempt.schedulerVersion ?? '空'}',
                  )
                  .join('\n'),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(record.word)),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, index) {
          final row = rows[index];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(row.$1),
            subtitle: Text(row.$2),
          );
        },
      ),
    );
  }
}

String _choiceLabel(StudyChoice? choice) => switch (choice) {
  StudyChoice.known => '认识',
  StudyChoice.unsure => '不确定',
  StudyChoice.unknown => '不认识',
  null => '空',
};

String _stageLabel(LearningStage stage) => switch (stage) {
  LearningStage.unlearned => '未学习',
  LearningStage.firstLayerLearning => '第一层学习中',
  LearningStage.contextStrengthening => '语境强化',
  LearningStage.waitingReview => '等待复习',
  LearningStage.reviewing => '复习中',
  LearningStage.reviewedAwaitingSchedule => '已复习，等待调度',
  LearningStage.familiar => '熟悉',
  LearningStage.mastered => '长期掌握',
};

String _dateTimeLabel(DateTime? value) =>
    value == null ? '空' : value.toIso8601String();

String _nullableNumber(num? value, String unit) =>
    value == null ? '空' : '$value $unit';

String _fluencyLabel(ReviewFluency? value) => switch (value) {
  ReviewFluency.normal => '正常',
  ReviewFluency.slow => '很慢',
  null => '空',
};

class _DebugData {
  const _DebugData({
    this.records = const [],
    this.tasks = const [],
    this.attempts = const [],
    this.dailyTasks = const [],
    this.dailyTarget = 0,
    this.progress,
    this.currentDate,
    this.contextArticles = const [],
  });

  final List<LearningRecord> records;
  final List<ReviewTask> tasks;
  final List<ReviewAttempt> attempts;
  final List<DailyNewWordTask> dailyTasks;
  final int dailyTarget;
  final VocabularyProgress? progress;
  final DateTime? currentDate;
  final List<ContextArticle> contextArticles;
}
