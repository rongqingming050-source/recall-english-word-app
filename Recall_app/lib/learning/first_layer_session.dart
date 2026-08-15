import 'dart:math';

import '../models/first_layer_word_state.dart';
import '../models/word.dart';

class FirstLayerSession {
  FirstLayerSession({required List<Word> words, Random? random})
    : _random = random ?? Random(),
      states = words
          .map((word) => FirstLayerWordState(word: word))
          .toList(growable: false) {
    if (words.isEmpty) {
      throw ArgumentError.value(words, 'words', 'must not be empty');
    }

    _pending.addAll(states);
    _advance();
  }

  final Random _random;
  final List<FirstLayerWordState> states;
  final List<FirstLayerWordState> _pending = [];
  final List<FirstLayerWordState> _secondAppearanceOrder = [];

  FirstLayerWordState? _current;
  FirstLayerWordState? _lastShown;
  bool _thirdAppearanceOrderPrepared = false;

  FirstLayerWordState get currentState {
    final current = _current;
    if (current == null) {
      throw StateError('The first-layer session is complete.');
    }
    return current;
  }

  bool get isComplete => _current == null;

  int get completedWordCount =>
      states.where((state) => state.isCompleted).length;

  void answer(StudyChoice choice) {
    final state = currentState;
    final isFirstAppearance = state.appearanceCount == 0;

    state.recordJudgment(choice);

    if (isFirstAppearance && choice != StudyChoice.known) {
      _pending
        ..add(state)
        ..add(state);
    }

    _lastShown = state;
    _advance();
  }

  FirstLayerSummary get summary {
    if (!isComplete) {
      throw StateError('A summary is only available after completion.');
    }

    return FirstLayerSummary.fromStates(states);
  }

  void _advance() {
    if (_pending.isEmpty) {
      _current = null;
      return;
    }

    _prepareThirdAppearanceOrder();
    final nextIndex = _findNextIndex();
    _current = _pending.removeAt(nextIndex);

    if (_current!.appearanceCount == 1) {
      _secondAppearanceOrder.add(_current!);
    }
  }

  void _prepareThirdAppearanceOrder() {
    if (_thirdAppearanceOrderPrepared ||
        !_pending.every((state) => state.appearanceCount == 2)) {
      return;
    }

    _thirdAppearanceOrderPrepared = true;

    if (_pending.length < 3) {
      return;
    }

    final shuffled = List<FirstLayerWordState>.of(_pending)..shuffle(_random);
    final isValidShuffle =
        shuffled.first != _lastShown &&
        !_hasSameOrder(shuffled, _secondAppearanceOrder);

    final thirdOrder = isValidShuffle
        ? shuffled
        : [..._secondAppearanceOrder.skip(1), _secondAppearanceOrder.first];

    _pending
      ..clear()
      ..addAll(thirdOrder);
  }

  bool _hasSameOrder(
    List<FirstLayerWordState> first,
    List<FirstLayerWordState> second,
  ) {
    if (first.length != second.length) {
      return false;
    }

    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) {
        return false;
      }
    }

    return true;
  }

  int _findNextIndex() {
    if (_thirdAppearanceOrderPrepared &&
        _pending.every((state) => state.appearanceCount == 2)) {
      return 0;
    }

    final unlearnedIndex = _pending.indexWhere(
      (state) => state.appearanceCount == 0 && state != _lastShown,
    );
    if (unlearnedIndex != -1) {
      return unlearnedIndex;
    }

    final eligibleStates = _pending
        .where((state) => state != _lastShown)
        .toSet();

    if (eligibleStates.isEmpty) {
      return 0;
    }

    var highestRemainingCount = 0;
    final candidates = <FirstLayerWordState>[];

    for (final state in eligibleStates) {
      final remainingCount = _pending
          .where((pendingState) => pendingState == state)
          .length;

      if (remainingCount > highestRemainingCount) {
        highestRemainingCount = remainingCount;
        candidates
          ..clear()
          ..add(state);
      } else if (remainingCount == highestRemainingCount) {
        candidates.add(state);
      }
    }

    final selectedState = candidates[_random.nextInt(candidates.length)];
    return _pending.indexOf(selectedState);
  }
}

class FirstLayerSummary {
  const FirstLayerSummary({
    required this.targetWordCount,
    required this.firstKnownCount,
    required this.firstUnsureCount,
    required this.firstUnknownCount,
    required this.threeAppearanceCount,
    required this.difficultWordCount,
  });

  final int targetWordCount;
  final int firstKnownCount;
  final int firstUnsureCount;
  final int firstUnknownCount;
  final int threeAppearanceCount;
  final int difficultWordCount;

  factory FirstLayerSummary.fromStates(List<FirstLayerWordState> states) =>
      FirstLayerSummary(
        targetWordCount: states.length,
        firstKnownCount: states
            .where((state) => state.firstJudgment == StudyChoice.known)
            .length,
        firstUnsureCount: states
            .where((state) => state.firstJudgment == StudyChoice.unsure)
            .length,
        firstUnknownCount: states
            .where((state) => state.firstJudgment == StudyChoice.unknown)
            .length,
        threeAppearanceCount: states
            .where((state) => state.appearanceCount == 3)
            .length,
        difficultWordCount: states.where((state) => state.isDifficult).length,
      );
}
