import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../context/context_article_generator.dart';
import '../data/learning_repository.dart';
import '../data/vocabulary_repository.dart';
import '../learning/context_session_service.dart';
import '../learning/daily_task_service.dart';
import '../models/learning_record.dart';
import '../review/review_queue.dart';
import '../settings/ai_service_settings.dart';
import 'ai_service_settings_page.dart';
import 'context_article_page.dart';
import 'debug_learning_data_page.dart';
import 'new_word_settings_page.dart';
import 'review_page.dart';
import 'study_page.dart';
import 'vocabulary_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.vocabulary,
    required this.articleGenerator,
    required this.aiServiceSettings,
    this.now = DateTime.now,
  });

  final LearningRepository repository;
  final VocabularyRepository vocabulary;
  final ArticleGenerator articleGenerator;
  final AiServiceSettings aiServiceSettings;
  final DateTime Function() now;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final DailyTaskService _dailyTaskService;
  late Future<_HomeData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dailyTaskService = DailyTaskService(
      repository: widget.repository,
      vocabulary: widget.vocabulary,
      now: widget.now,
    );
    _refresh();
  }

  void _refresh() {
    _dataFuture = _loadData();
  }

  Future<_HomeData> _loadData() async {
    final plan = await _dailyTaskService.loadOrCreateToday();
    final results = await Future.wait([
      _dailyTaskService.getDueFormalReviewTasks(),
      _dailyTaskService.getVocabularyProgress(),
      widget.repository.getAllReviewAttempts(),
    ]);
    final dueTasks = results[0] as List<ReviewTask>;
    final attempts = results[2] as List<ReviewAttempt>;
    final today = localDateOnly(widget.now());
    final dueWordIds = dueTasks.map((task) => task.wordId).toSet();
    final reviewedTodayWordIds = attempts
        .where((attempt) {
          final actualDate = attempt.actualReviewDate ?? attempt.reviewedAt;
          return localDateOnly(actualDate) == today &&
              widget.vocabulary.findById(attempt.wordId) != null;
        })
        .map((attempt) => attempt.wordId)
        .toSet();
    final reviewCompletedToday = reviewedTodayWordIds.difference(dueWordIds);
    return _HomeData(
      plan: plan,
      dueTasks: dueTasks,
      progress: results[1] as VocabularyProgress,
      reviewCompletedToday: reviewCompletedToday.length,
      reviewTotalToday: reviewCompletedToday.length + dueTasks.length,
    );
  }

  Future<void> _startToday(_HomeData data) async {
    try {
      if (data.dueTasks.isNotEmpty) {
        final items = ReviewQueueLoader(widget.vocabulary).load(data.dueTasks);
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReviewPage(
              items: items,
              repository: widget.repository,
              now: widget.now,
            ),
          ),
        );
        if (!mounted) return;
        final refreshed = await _loadData();
        if (refreshed.dueTasks.isEmpty) {
          await _openNewWordWork(refreshed.plan);
        }
      } else {
        await _openNewWordWork(data.plan);
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('今日任务加载失败：$error')));
      }
    } finally {
      if (mounted) setState(_refresh);
    }
  }

  Future<void> _openNewWordWork(TodayTaskPlan plan) async {
    if (plan.contextWords.isNotEmpty) {
      final data = await ContextSessionService(
        repository: widget.repository,
      ).load(plan.contextWords);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ContextArticlePage(
            request: data.request,
            focusWords: data.focusWords,
            targetWords: plan.contextWords,
            repository: widget.repository,
            summary: data.summary,
            articleGenerator: widget.articleGenerator,
            now: widget.now,
          ),
        ),
      );
      return;
    }
    if (plan.firstLayerWords.isEmpty || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StudyPage(
          words: plan.firstLayerWords,
          contextTargetWords: plan.firstLayerWords,
          repository: widget.repository,
          articleGenerator: widget.articleGenerator,
          now: widget.now,
        ),
      ),
    );
  }

  Future<void> _openVocabulary() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VocabularyPage(
          vocabulary: widget.vocabulary,
          dailyTaskService: _dailyTaskService,
        ),
      ),
    );
    if (mounted) setState(_refresh);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NewWordSettingsPage(repository: widget.repository),
      ),
    );
    if (mounted) setState(_refresh);
  }

  Future<void> _openAiSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AiServiceSettingsPage(settings: widget.aiServiceSettings),
      ),
    );
  }

  void _handleMenuAction(_HomeMenuAction action) {
    switch (action) {
      case _HomeMenuAction.aiSettings:
        _openAiSettings();
      case _HomeMenuAction.newWordSettings:
        _openSettings();
      case _HomeMenuAction.debugLearningData:
        if (!kDebugMode) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DebugLearningDataPage(
              repository: widget.repository,
              vocabulary: widget.vocabulary,
              dailyTaskService: _dailyTaskService,
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _homeBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final outerMargin = constraints.maxWidth >= 700 ? 8.0 : 10.0;
            final cardRadius = constraints.maxWidth >= 700 ? 40.0 : 24.0;
            final minHeight = math.max(
              0.0,
              constraints.maxHeight - outerMargin * 2,
            );

            return RefreshIndicator(
              color: _homeAccent,
              onRefresh: () async {
                setState(_refresh);
                await _dataFuture;
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(outerMargin),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minHeight),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(cardRadius),
                    ),
                    child: FutureBuilder<_HomeData>(
                      future: _dataFuture,
                      builder: (context, snapshot) {
                        final horizontalPadding = _clampDouble(
                          constraints.maxWidth * 0.05,
                          22,
                          64,
                        );
                        final verticalPadding = constraints.maxWidth >= 700
                            ? 58.0
                            : 26.0;
                        final contentWidth = math.max(
                          0.0,
                          constraints.maxWidth -
                              outerMargin * 2 -
                              horizontalPadding * 2,
                        );
                        final textScale = MediaQuery.textScalerOf(
                          context,
                        ).scale(1);
                        final minimumContentHeight = textScale > 1.3
                            ? 680.0
                            : 420.0;
                        final contentHeight = math.max(
                          minimumContentHeight,
                          constraints.maxHeight -
                              outerMargin * 2 -
                              verticalPadding * 2,
                        );

                        return Padding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            verticalPadding,
                            horizontalPadding,
                            verticalPadding,
                          ),
                          child: _buildHomeContent(
                            context,
                            snapshot,
                            contentWidth,
                            contentHeight,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHomeContent(
    BuildContext context,
    AsyncSnapshot<_HomeData> snapshot,
    double contentWidth,
    double contentHeight,
  ) {
    if (snapshot.connectionState != ConnectionState.done) {
      return SizedBox(
        height: contentHeight,
        child: const Center(
          child: CircularProgressIndicator(color: _homeAccent),
        ),
      );
    }
    if (snapshot.hasError) {
      return SizedBox(
        height: contentHeight,
        child: Center(
          child: Text(
            '今日任务读取失败：${snapshot.error}',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final data = snapshot.requireData;
    final isWide = contentWidth >= 640;
    final titleSize = _clampDouble(contentWidth * 0.03, 24, 32);
    final secondarySize = _clampDouble(contentWidth * 0.016, 15, 18);
    final statSize = _clampDouble(contentWidth * 0.024, 22, 28);
    final progress = data.progress.totalCount == 0
        ? 0.0
        : (data.progress.lifecycleCount / data.progress.totalCount)
              .clamp(0.0, 1.0)
              .toDouble();
    final newTarget = data.plan.actualTaskCount;
    final newCompleted = data.plan.completedTodayCount;
    final useStackedProgressSummary =
        !isWide && MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final allDone = data.dueTasks.isEmpty && data.plan.pendingNewWordCount == 0;

    return SizedBox(
      height: contentHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, titleSize, isWide),
              SizedBox(height: isWide ? 30 : 20),
              _ProgressSummary(
                progress: progress,
                lifecycleCount: data.progress.lifecycleCount,
                totalCount: data.progress.totalCount,
                fontSize: secondarySize,
                stacked: useStackedProgressSummary,
              ),
              SizedBox(height: isWide ? 22 : 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: _homeProgressBackground,
                  valueColor: const AlwaysStoppedAnimation<Color>(_homeAccent),
                ),
              ),
              SizedBox(height: isWide ? 58 : 34),
              _CountStat(
                label: '新词',
                value: newCompleted,
                target: newTarget,
                fontSize: statSize,
                key: const ValueKey('pending-new-word-count'),
              ),
              SizedBox(height: isWide ? 34 : 20),
              _CountStat(
                label: '复习词',
                value: data.reviewCompletedToday,
                target: data.reviewTotalToday,
                fontSize: statSize,
                key: const ValueKey('due-review-count'),
              ),
              const Spacer(),
              SizedBox(height: isWide ? 28 : 24),
              if (allDone)
                _buildCompletedState(isWide, statSize)
              else
                _buildStartButton(data, isWide, contentWidth),
            ],
          ),
          const Positioned(
            left: 0,
            top: 0,
            width: 1,
            height: 1,
            child: Opacity(opacity: 0, child: Text('Recall')),
          ),
          Positioned(
            left: 0,
            top: 0,
            width: 1,
            height: 1,
            child: Opacity(
              opacity: 0,
              child: Text('待复习：${data.dueTasks.length}'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, double titleSize, bool isWide) {
    final title = Text(
      widget.vocabulary.book.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: _homeText,
        fontSize: titleSize,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.8,
        height: 1.1,
      ),
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<_HomeMenuAction>(
          tooltip: '更多设置',
          icon: const Icon(Icons.more_horiz_rounded),
          iconSize: isWide ? 22 : 22,
          padding: EdgeInsets.zero,
          onSelected: _handleMenuAction,
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: _HomeMenuAction.aiSettings,
              child: Text('AI 服务设置'),
            ),
            const PopupMenuItem(
              value: _HomeMenuAction.newWordSettings,
              child: Text('每日新词设置'),
            ),
            if (kDebugMode)
              const PopupMenuItem(
                value: _HomeMenuAction.debugLearningData,
                child: Text('学习数据（调试）'),
              ),
          ],
        ),
        _VocabularyLink(onTap: _openVocabulary, compact: !isWide),
      ],
    );

    if (!isWide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerRight, child: actions),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: title),
        const SizedBox(width: 14),
        actions,
      ],
    );
  }

  Widget _buildStartButton(_HomeData data, bool isWide, double contentWidth) {
    final height = isWide ? _clampDouble(contentWidth * 0.08, 78, 92) : 70.0;
    final radius = height / 2;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: _homeAccent,
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                BoxShadow(
                  color: _homeAccent.withValues(alpha: 0.24),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: const ValueKey('start-today'),
                borderRadius: BorderRadius.circular(radius),
                onTap: () => _startToday(data),
                child: Center(
                  child: Text(
                    '开始学习',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isWide ? 27 : 24,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _startToday(data),
              child: ExcludeSemantics(
                child: Center(
                  child: Opacity(
                    opacity: 0,
                    child: Text(
                      '开始今日学习',
                      style: TextStyle(fontSize: isWide ? 27 : 24),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedState(bool isWide, double statSize) {
    return Container(
      height: isWide ? 88 : 70,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _homeCompletedBackground,
        borderRadius: BorderRadius.circular(isWide ? 44 : 35),
      ),
      child: Text(
        '今日任务已完成',
        key: const ValueKey('today-complete'),
        style: TextStyle(
          color: _homeAccent,
          fontSize: _clampDouble(statSize * 0.72, 18, 22),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

const _homeBackground = Color(0xFFE6F9F6);
const _homeAccent = Color(0xFF08C7A6);
const _homeText = Color(0xFF333333);
const _homeSecondaryText = Color(0xFF9B9B9B);
const _homeProgressBackground = Color(0xFFF1F1F1);
const _homeCompletedBackground = Color(0xFFE8FBF7);

enum _HomeMenuAction { aiSettings, newWordSettings, debugLearningData }

class _VocabularyLink extends StatelessWidget {
  const _VocabularyLink({required this.onTap, required this.compact});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 24.0 : 25.0;
    final textSize = compact ? 18.0 : 20.0;
    return Tooltip(
      message: '词表',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.menu_book_outlined,
                  color: _homeText,
                  size: iconSize,
                ),
                const SizedBox(width: 8),
                Text(
                  '词表',
                  style: TextStyle(
                    color: _homeText,
                    fontSize: textSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountStat extends StatelessWidget {
  const _CountStat({
    super.key,
    required this.label,
    required this.value,
    required this.target,
    required this.fontSize,
  });

  final String label;
  final int value;
  final int target;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label：'),
          TextSpan(
            text: '$value/$target',
            style: const TextStyle(fontWeight: FontWeight.w400),
          ),
        ],
      ),
      style: TextStyle(
        color: _homeText,
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        height: 1.15,
      ),
    );
  }
}

class _ProgressSummary extends StatelessWidget {
  const _ProgressSummary({
    required this.progress,
    required this.lifecycleCount,
    required this.totalCount,
    required this.fontSize,
    required this.stacked,
  });

  final double progress;
  final int lifecycleCount;
  final int totalCount;
  final double fontSize;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: _homeSecondaryText,
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
    );
    final progressText = Text(
      '进度: ${(progress * 100).toStringAsFixed(1)}%',
      style: style,
    );
    final countText = Text('$lifecycleCount/$totalCount词', style: style);

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          progressText,
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerRight, child: countText),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [progressText, countText],
    );
  }
}

double _clampDouble(double value, double min, double max) {
  return value.clamp(min, max).toDouble();
}

class _HomeData {
  const _HomeData({
    required this.plan,
    required this.dueTasks,
    required this.progress,
    required this.reviewCompletedToday,
    required this.reviewTotalToday,
  });

  final TodayTaskPlan plan;
  final List<ReviewTask> dueTasks;
  final VocabularyProgress progress;
  final int reviewCompletedToday;
  final int reviewTotalToday;
}
