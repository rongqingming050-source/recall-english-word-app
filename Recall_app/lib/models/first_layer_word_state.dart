import 'word.dart';

enum StudyChoice { known, unsure, unknown }

class FirstLayerWordState {
  FirstLayerWordState({required this.word});

  final Word word;
  final List<StudyChoice> _judgments = [];

  List<StudyChoice> get judgments => List.unmodifiable(_judgments);

  int get appearanceCount => _judgments.length;

  int get currentAppearanceNumber => _judgments.length + 1;

  StudyChoice? get firstJudgment => _judgmentAt(0);

  StudyChoice? get secondJudgment => _judgmentAt(1);

  StudyChoice? get thirdJudgment => _judgmentAt(2);

  bool get isCompleted {
    if (_judgments.isEmpty) {
      return false;
    }

    return firstJudgment == StudyChoice.known || _judgments.length == 3;
  }

  bool get isDifficult =>
      _judgments.length == 3 && thirdJudgment == StudyChoice.unknown;

  void recordJudgment(StudyChoice choice) {
    if (isCompleted || _judgments.length == 3) {
      throw StateError('${word.word} has completed the first layer.');
    }

    _judgments.add(choice);
  }

  StudyChoice? _judgmentAt(int index) {
    return index < _judgments.length ? _judgments[index] : null;
  }
}
