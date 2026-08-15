import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../context/context_article_generator.dart';
import '../data/learning_repository.dart';
import '../learning/first_layer_session.dart';
import '../learning/first_review_service.dart';
import '../models/context_article.dart';
import '../models/learning_record.dart';
import '../models/word.dart';
import 'completion_page.dart';

enum ContextArticleViewState { loading, success, error, cached }

class ContextArticlePage extends StatefulWidget {
  const ContextArticlePage({
    super.key,
    required this.request,
    required this.focusWords,
    required this.targetWords,
    required this.repository,
    required this.summary,
    required this.articleGenerator,
    this.now,
  });

  final ContextArticleRequest request;
  final List<Word> focusWords;
  final List<Word> targetWords;
  final LearningRepository repository;
  final FirstLayerSummary summary;
  final ArticleGenerator articleGenerator;
  final DateTime Function()? now;

  @override
  State<ContextArticlePage> createState() => _ContextArticlePageState();
}

class _ContextArticlePageState extends State<ContextArticlePage> {
  final List<TapGestureRecognizer> _recognizers = [];
  ContextArticleViewState _viewState = ContextArticleViewState.loading;
  ContextArticle? _article;
  bool _isFinishing = false;
  bool _requestInFlight = false;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('语境强化')),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: switch (_viewState) {
            ContextArticleViewState.loading => const Center(
              key: ValueKey('context-loading'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text('正在生成语境文章……'),
                ],
              ),
            ),
            ContextArticleViewState.error => _buildError(),
            ContextArticleViewState.success ||
            ContextArticleViewState.cached => _buildArticle(),
          },
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      key: const ValueKey('context-error'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 48),
          const SizedBox(height: 16),
          const Text('语境文章生成失败，请检查 AI 服务设置或网络。', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton(
            key: const ValueKey('context-retry'),
            onPressed: _requestInFlight ? null : _generate,
            child: const Text('重新生成'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const ValueKey('context-skip'),
            onPressed: _isFinishing ? null : _skip,
            child: const Text('暂时跳过'),
          ),
        ],
      ),
    );
  }

  Widget _buildArticle() {
    final article = _article!;
    return Column(
      key: ValueKey(
        _viewState == ContextArticleViewState.cached
            ? 'context-cached'
            : 'context-success',
      ),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_viewState == ContextArticleViewState.cached)
          const Align(
            alignment: Alignment.centerLeft,
            child: Chip(label: Text('已读取缓存')),
          ),
        Text(
          article.title,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: SingleChildScrollView(
            child: RichText(
              key: const ValueKey('context-article'),
              text: TextSpan(
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontFamily: 'serif',
                  height: 1.7,
                ),
                children: _buildArticleSpans(article),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          key: const ValueKey('context-regenerate'),
          onPressed: _requestInFlight ? null : () => _generate(force: true),
          child: const Text('重新生成一篇'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const ValueKey('context-finish'),
          onPressed: _isFinishing ? null : _finishReading,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('阅读完成'),
          ),
        ),
      ],
    );
  }

  Future<void> _generate({bool force = false}) async {
    if (_requestInFlight) return;
    _requestInFlight = true;
    if (mounted) {
      setState(() => _viewState = ContextArticleViewState.loading);
    }
    try {
      final result = force
          ? await widget.articleGenerator.regenerateArticle(widget.request)
          : await widget.articleGenerator.generateArticle(widget.request);
      if (!mounted) return;
      setState(() {
        _article = result.article;
        _viewState = result.isCached
            ? ContextArticleViewState.cached
            : ContextArticleViewState.success;
      });
    } on Object {
      if (mounted) {
        setState(() => _viewState = ContextArticleViewState.error);
      }
    } finally {
      _requestInFlight = false;
    }
  }

  Future<void> _skip() async {
    if (_isFinishing) return;
    setState(() => _isFinishing = true);
    try {
      await widget.articleGenerator.skipArticle(widget.request);
      await _completeLearning();
    } on Object {
      if (mounted) {
        setState(() => _isFinishing = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('跳过状态保存失败，请重试')));
      }
    }
  }

  Future<void> _finishReading() async {
    if (_isFinishing) return;
    setState(() => _isFinishing = true);
    try {
      await _completeLearning();
    } on Object {
      if (mounted) {
        setState(() => _isFinishing = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('学习状态保存失败，请重试')));
      }
    }
  }

  Future<void> _completeLearning() async {
    final now = (widget.now ?? DateTime.now)();
    await FirstReviewService(
      repository: widget.repository,
    ).scheduleTargetWords(widget.targetWords, now: now);
    await widget.repository.markDailyTasksCompleted(
      widget.targetWords.map((word) => word.id),
      completedAt: now,
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement<void, bool>(
      MaterialPageRoute<void>(
        builder: (_) => CompletionPage(summary: widget.summary),
      ),
      result: true,
    );
  }

  List<TextSpan> _buildArticleSpans(ContextArticle article) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    final usedIds = article.usedWordIds.toSet();
    final wordsBySurface = <String, Word>{};
    for (final word in widget.focusWords) {
      if (!usedIds.contains(word.id)) continue;
      for (final surface in surfaceForms(word.word)) {
        wordsBySurface[surface.toLowerCase()] = word;
      }
    }
    if (wordsBySurface.isEmpty) return [TextSpan(text: article.articleText)];

    final pattern = wordsBySurface.keys.map(RegExp.escape).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final matches = RegExp(
      '(^|[^A-Za-z])(${pattern.join('|')})(?=\$|[^A-Za-z])',
      caseSensitive: false,
    ).allMatches(article.articleText);
    final spans = <TextSpan>[];
    var previousEnd = 0;
    for (final match in matches) {
      final wordStart = match.start + (match.group(1)?.length ?? 0);
      final wordEnd = match.end;
      if (wordStart > previousEnd) {
        spans.add(
          TextSpan(text: article.articleText.substring(previousEnd, wordStart)),
        );
      }
      final matchedText = article.articleText.substring(wordStart, wordEnd);
      final word = wordsBySurface[matchedText.toLowerCase()]!;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => _showWordDetails(word);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: matchedText,
          style: const TextStyle(fontWeight: FontWeight.bold),
          recognizer: recognizer,
        ),
      );
      previousEnd = wordEnd;
    }
    if (previousEnd < article.articleText.length) {
      spans.add(TextSpan(text: article.articleText.substring(previousEnd)));
    }
    return spans;
  }

  Future<void> _showWordDetails(Word word) async {
    final now = (widget.now ?? DateTime.now)();
    var isScheduled = await widget.repository.hasReviewTask(
      word,
      nextLocalDate(now),
    );
    if (!mounted) return;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              8,
              24,
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      word.word,
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 16),
                    Flexible(
                      child: Text(
                        word.phonetic,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  word.meaning,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(word.example),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: isScheduled
                      ? null
                      : () async {
                          await widget.repository.overrideReviewTaskToTomorrow(
                            word,
                            now: now,
                          );
                          if (context.mounted) {
                            setSheetState(() => isScheduled = true);
                          }
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(isScheduled ? '已安排明天复习' : '重学'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }
}
