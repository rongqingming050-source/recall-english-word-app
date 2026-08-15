import '../models/first_layer_word_state.dart';
import '../models/word.dart';

class ContextWordSelector {
  const ContextWordSelector({this.maxWords = 15});

  final int maxWords;

  List<Word> select(List<FirstLayerWordState> states) {
    if (maxWords <= 0) {
      return const [];
    }

    final rankedStates = states.indexed.toList()
      ..sort((first, second) {
        final priorityComparison = _priority(
          first.$2,
        ).compareTo(_priority(second.$2));

        return priorityComparison != 0
            ? priorityComparison
            : first.$1.compareTo(second.$1);
      });

    return rankedStates
        .take(maxWords)
        .map((entry) => entry.$2.word)
        .toList(growable: false);
  }

  int _priority(FirstLayerWordState state) {
    if (state.isDifficult) {
      return 0;
    }

    return switch (state.firstJudgment) {
      StudyChoice.unknown => 1,
      StudyChoice.unsure => 2,
      StudyChoice.known => 3,
      null => 4,
    };
  }
}
