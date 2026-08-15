import 'package:flutter/material.dart';

import '../context/context_article_generator.dart';
import '../context/context_word_selector.dart';
import '../data/learning_repository.dart';
import '../data/memory_learning_repository.dart';
import '../learning/first_layer_session.dart';
import '../learning/context_session_service.dart';
import '../models/first_layer_word_state.dart';
import '../models/word.dart';
import 'context_article_page.dart';

class StudyPage extends StatefulWidget {
  const StudyPage({
    super.key,
    required this.words,
    this.contextWordSelector = const ContextWordSelector(),
    this.articleGenerator,
    this.repository,
    this.now,
    this.contextTargetWords,
  });

  final List<Word> words;
  final ContextWordSelector contextWordSelector;
  final ArticleGenerator? articleGenerator;
  final LearningRepository? repository;
  final DateTime Function()? now;
  final List<Word>? contextTargetWords;

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  late final FirstLayerSession _session;
  late final LearningRepository _repository;
  bool _isMeaningVisible = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _session = FirstLayerSession(words: widget.words);
    _repository = widget.repository ?? MemoryLearningRepository();
  }

  void _showMeaning() {
    setState(() {
      _isMeaningVisible = true;
    });
  }

  Future<void> _answer(StudyChoice choice) async {
    if (!_isMeaningVisible || _isSaving) {
      return;
    }

    final answeredState = _session.currentState;
    _session.answer(choice);

    if (answeredState.isCompleted) {
      setState(() => _isSaving = true);
      try {
        await _repository.saveFirstLayerResults([
          answeredState,
        ], completedAt: (widget.now ?? DateTime.now)());
      } on Object {
        if (mounted) {
          setState(() => _isSaving = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('学习记录保存失败，请重试')));
        }
        return;
      }
    }

    if (_session.isComplete) {
      try {
        final targetWords = widget.contextTargetWords ?? widget.words;
        final contextData = await ContextSessionService(
          repository: _repository,
          wordSelector: widget.contextWordSelector,
        ).load(targetWords);

        if (!mounted) return;
        final continuedToCompletion = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => ContextArticlePage(
              request: contextData.request,
              focusWords: contextData.focusWords,
              targetWords: targetWords,
              repository: _repository,
              summary: contextData.summary,
              articleGenerator:
                  widget.articleGenerator ?? FakeArticleGenerator(),
              now: widget.now,
            ),
          ),
        );
        if (mounted && continuedToCompletion != true) {
          Navigator.of(context).pop();
        }
      } on Object {
        if (mounted) {
          setState(() => _isSaving = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('语境强化内容加载失败，请重试')));
        }
      }
      return;
    }

    setState(() {
      _isMeaningVisible = false;
      _isSaving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_session.isComplete) {
      return Scaffold(
        appBar: AppBar(title: const Text('第一层学习')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final currentWord = _session.currentState.word;

    return Scaffold(
      appBar: AppBar(
        title: const Text('第一层学习'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '已完成 ${_session.completedWordCount} / ${widget.words.length}',
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                currentWord.word,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.displaySmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 16),
                            _AppearanceDots(
                              completedAppearances:
                                  _session.currentState.appearanceCount,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          currentWord.phonetic,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 32),
                        if (!_isMeaningVisible)
                          OutlinedButton(
                            onPressed: _showMeaning,
                            child: const Text('查看释义'),
                          )
                        else
                          Column(
                            children: [
                              Text(
                                currentWord.meaning,
                                textAlign: TextAlign.center,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                currentWord.example,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_isMeaningVisible) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: _isSaving
                            ? null
                            : () => _answer(StudyChoice.known),
                        child: const Text('认识'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: _isSaving
                            ? null
                            : () => _answer(StudyChoice.unsure),
                        child: const Text('不确定'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: _isSaving
                            ? null
                            : () => _answer(StudyChoice.unknown),
                        child: const Text('不认识'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AppearanceDots extends StatelessWidget {
  const _AppearanceDots({required this.completedAppearances});

  static const _totalAppearances = 3;

  final int completedAppearances;

  @override
  Widget build(BuildContext context) {
    final completedCount = completedAppearances.clamp(0, _totalAppearances);
    final inactiveColor = Theme.of(context).colorScheme.outlineVariant;

    return Semantics(
      label: '已学习 $completedCount 次，共 $_totalAppearances 次',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(_totalAppearances, (index) {
          final isCompleted = index >= _totalAppearances - completedCount;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Container(
              key: ValueKey('appearance-dot-$index'),
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: isCompleted ? Colors.green : inactiveColor,
                shape: BoxShape.circle,
              ),
            ),
          );
        }),
      ),
    );
  }
}
