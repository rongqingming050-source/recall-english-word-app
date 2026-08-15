import 'package:flutter/material.dart';

import '../data/learning_repository.dart';
import '../models/first_layer_word_state.dart';
import '../models/learning_record.dart';
import '../review/review_queue.dart';
import '../review/review_scheduler.dart';
import 'review_completion_page.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({
    super.key,
    required this.items,
    required this.repository,
    this.now,
  });

  final List<ReviewQueueItem> items;
  final LearningRepository repository;
  final DateTime Function()? now;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final Stopwatch _stopwatch = Stopwatch();
  final List<ReviewAttempt> _attempts = [];
  late final AnimationController _countdownController;
  int _index = 0;
  int? _reactionTimeMs;
  bool _meaningVisible = false;
  bool _submitting = false;

  ReviewQueueItem get _current => widget.items[_index];

  @override
  void initState() {
    super.initState();
    if (widget.items.isEmpty) {
      throw ArgumentError('Review queue must not be empty.');
    }
    _countdownController = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: ReviewPolicy.slowThresholdMilliseconds,
      ),
    )..forward();
    WidgetsBinding.instance.addObserver(this);
    _stopwatch.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_meaningVisible) return;
    if (state == AppLifecycleState.resumed) {
      _stopwatch.start();
      _countdownController.forward();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _stopwatch.stop();
      _countdownController.stop(canceled: false);
    }
  }

  void _revealMeaning() {
    if (_meaningVisible) return;
    _stopwatch.stop();
    _countdownController.stop(canceled: false);
    setState(() {
      _reactionTimeMs = _stopwatch.elapsedMilliseconds;
      _meaningVisible = true;
    });
  }

  Future<void> _submit(StudyChoice result) async {
    final reaction = _reactionTimeMs;
    if (!_meaningVisible || reaction == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      final attempt = await widget.repository.completeReviewTask(
        reviewTaskId: _current.task.id,
        result: result,
        reactionTimeMs: reaction,
        reviewedAt: (widget.now ?? DateTime.now)(),
      );
      _attempts.add(attempt);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('复习结果保存失败：$error')));
      }
      return;
    }

    if (!mounted) return;
    if (_index == widget.items.length - 1) {
      final summary = ReviewSummary(
        total: _attempts.length,
        known: _attempts
            .where((value) => value.result == StudyChoice.known)
            .length,
        unsure: _attempts
            .where((value) => value.result == StudyChoice.unsure)
            .length,
        unknown: _attempts
            .where((value) => value.result == StudyChoice.unknown)
            .length,
        knownNormal: _attempts
            .where(
              (value) =>
                  value.result == StudyChoice.known &&
                  value.fluency == ReviewFluency.normal,
            )
            .length,
        knownSlow: _attempts
            .where(
              (value) =>
                  value.result == StudyChoice.known &&
                  value.fluency == ReviewFluency.slow,
            )
            .length,
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ReviewCompletionPage(summary: summary),
        ),
      );
      return;
    }

    setState(() {
      _index += 1;
      _meaningVisible = false;
      _reactionTimeMs = null;
      _submitting = false;
      _stopwatch
        ..reset()
        ..start();
      _countdownController
        ..reset()
        ..forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    final word = _current.word;
    return Scaffold(
      appBar: AppBar(
        title: const Text('正式复习'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('${_index + 1} / ${widget.items.length}'),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        word.word,
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        word.phonetic,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 24),
                      if (!_meaningVisible) ...[
                        _RecallCountdownIndicator(
                          progress: _countdownController,
                        ),
                        const SizedBox(height: 20),
                        OutlinedButton(
                          onPressed: _revealMeaning,
                          child: const Text('查看释义'),
                        ),
                      ] else ...[
                        Text(
                          word.meaning,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 20),
                        Text(word.example, textAlign: TextAlign.center),
                      ],
                    ],
                  ),
                ),
              ),
              if (_meaningVisible)
                Row(
                  children: [
                    for (final entry in const [
                      (StudyChoice.known, '认识'),
                      (StudyChoice.unsure, '不确定'),
                      (StudyChoice.unknown, '不认识'),
                    ].indexed) ...[
                      if (entry.$1 > 0) const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: _submitting
                              ? null
                              : () => _submit(entry.$2.$1),
                          child: Text(entry.$2.$2),
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopwatch.stop();
    _countdownController.dispose();
    super.dispose();
  }
}

class _RecallCountdownIndicator extends StatelessWidget {
  const _RecallCountdownIndicator({required this.progress});

  static const _progressColor = Color(0xFF2E7D32);

  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        final isComplete = progress.value >= 1;
        return Semantics(
          label: '回忆倒计时',
          value: isComplete ? '已结束' : '进行中',
          child: SizedBox.square(
            dimension: 56,
            child: CircularProgressIndicator(
              key: const ValueKey('review-recall-progress'),
              value: progress.value,
              strokeWidth: 6,
              strokeCap: StrokeCap.round,
              backgroundColor: colors.surfaceContainerHighest,
              color: _progressColor,
            ),
          ),
        );
      },
    );
  }
}
