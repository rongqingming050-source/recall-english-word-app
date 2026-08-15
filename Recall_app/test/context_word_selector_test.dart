import 'package:flutter_test/flutter_test.dart';
import 'package:recall_app/context/context_word_selector.dart';
import 'package:recall_app/models/first_layer_word_state.dart';
import 'package:recall_app/models/word.dart';

void main() {
  const selector = ContextWordSelector(maxWords: 4);

  test('unknown words are selected before unsure and known words', () {
    final known = _state('known', [StudyChoice.known]);
    final unsure = _state('unsure', [
      StudyChoice.unsure,
      StudyChoice.known,
      StudyChoice.known,
    ]);
    final unknown = _state('unknown', [
      StudyChoice.unknown,
      StudyChoice.known,
      StudyChoice.known,
    ]);

    final selected = selector.select([known, unsure, unknown]);

    expect(selected.map((word) => word.word), ['unknown', 'unsure', 'known']);
  });

  test('difficult words have the highest context priority', () {
    final regularUnknown = _state('regular', [
      StudyChoice.unknown,
      StudyChoice.known,
      StudyChoice.known,
    ]);
    final difficult = _state('difficult', [
      StudyChoice.unknown,
      StudyChoice.unknown,
      StudyChoice.unknown,
    ]);

    final selected = selector.select([regularUnknown, difficult]);

    expect(selected.first.word, 'difficult');
  });

  test('selection respects the configured maximum', () {
    final states = List.generate(
      6,
      (index) => _state('word$index', [StudyChoice.known]),
    );

    expect(selector.select(states), hasLength(4));
  });
}

FirstLayerWordState _state(String name, List<StudyChoice> choices) {
  final state = FirstLayerWordState(
    word: Word(
      word: name,
      phonetic: '/test/',
      meaning: '测试',
      example: 'Example.',
    ),
  );

  for (final choice in choices) {
    state.recordJudgment(choice);
  }

  return state;
}
