import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:recall_app/learning/first_layer_session.dart';
import 'package:recall_app/models/first_layer_word_state.dart';
import 'package:recall_app/models/word.dart';

const words = <Word>[
  Word(word: 'alpha', phonetic: '/a/', meaning: '甲', example: 'Alpha.'),
  Word(word: 'bravo', phonetic: '/b/', meaning: '乙', example: 'Bravo.'),
  Word(word: 'charlie', phonetic: '/c/', meaning: '丙', example: 'Charlie.'),
  Word(word: 'delta', phonetic: '/d/', meaning: '丁', example: 'Delta.'),
];

void main() {
  group('FirstLayerSession', () {
    test('a word first marked known appears only once', () {
      final session = _session(words.take(2).toList());

      expect(session.currentState.word.word, 'alpha');
      session.answer(StudyChoice.known);
      expect(session.currentState.word.word, 'bravo');
      session.answer(StudyChoice.known);

      expect(session.isComplete, isTrue);
      expect(session.states.first.appearanceCount, 1);
      expect(session.states.first.judgments, [StudyChoice.known]);
    });

    test('a word first marked unsure appears exactly three times', () {
      final session = _session([words.first]);

      session.answer(StudyChoice.unsure);
      session.answer(StudyChoice.known);
      session.answer(StudyChoice.known);

      expect(session.isComplete, isTrue);
      expect(session.states.single.appearanceCount, 3);
      expect(session.states.single.firstJudgment, StudyChoice.unsure);
      expect(session.states.single.secondJudgment, StudyChoice.known);
      expect(session.states.single.thirdJudgment, StudyChoice.known);
    });

    test('a word first marked unknown appears exactly three times', () {
      final session = _session([words.first]);

      session.answer(StudyChoice.unknown);
      session.answer(StudyChoice.unsure);
      session.answer(StudyChoice.known);

      expect(session.isComplete, isTrue);
      expect(session.states.single.appearanceCount, 3);
      expect(session.states.single.firstJudgment, StudyChoice.unknown);
    });

    test('a third unknown marks difficult and never creates a fourth turn', () {
      final session = _session([words.first]);

      session.answer(StudyChoice.unknown);
      session.answer(StudyChoice.unsure);
      session.answer(StudyChoice.unknown);

      expect(session.isComplete, isTrue);
      expect(session.states.single.appearanceCount, 3);
      expect(session.states.single.isDifficult, isTrue);
      expect(session.summary.difficultWordCount, 1);
      expect(
        () => session.answer(StudyChoice.unknown),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'repeat words do not appear consecutively when alternatives exist',
      () {
        final session = _session(words.take(3).toList());
        final shownWords = <String>[];
        var steps = 0;

        while (!session.isComplete) {
          shownWords.add(session.currentState.word.word);
          session.answer(StudyChoice.unknown);
          steps += 1;
          expect(steps, lessThanOrEqualTo(9));
        }

        for (var index = 1; index < shownWords.length; index++) {
          expect(shownWords[index], isNot(shownWords[index - 1]));
        }
      },
    );

    test('multiple weak words finish their repeat queue', () {
      final session = _session(words.take(3).toList());
      final firstChoices = <String, StudyChoice>{
        'alpha': StudyChoice.unsure,
        'bravo': StudyChoice.unknown,
        'charlie': StudyChoice.unsure,
      };
      var steps = 0;

      while (!session.isComplete) {
        final state = session.currentState;
        final choice = state.appearanceCount == 0
            ? firstChoices[state.word.word]!
            : StudyChoice.known;
        session.answer(choice);
        steps += 1;
        expect(steps, lessThanOrEqualTo(9));
      }

      expect(steps, 9);
      expect(
        session.states.map((state) => state.appearanceCount),
        everyElement(3),
      );
      expect(session.summary.threeAppearanceCount, 3);
    });

    test('all words first marked known finish after one pass', () {
      final session = _session(words);
      var steps = 0;

      while (!session.isComplete) {
        session.answer(StudyChoice.known);
        steps += 1;
        expect(steps, lessThanOrEqualTo(words.length));
      }

      expect(steps, words.length);
      expect(session.summary.firstKnownCount, words.length);
      expect(session.summary.threeAppearanceCount, 0);
    });

    test('all words first marked unknown finish without a dead loop', () {
      final session = _session(words);
      var steps = 0;

      while (!session.isComplete) {
        session.answer(StudyChoice.unknown);
        steps += 1;
        expect(steps, lessThanOrEqualTo(words.length * 3));
      }

      expect(steps, words.length * 3);
      expect(session.summary.firstUnknownCount, words.length);
      expect(session.summary.threeAppearanceCount, words.length);
      expect(session.summary.difficultWordCount, words.length);
      expect(
        session.states.map((state) => state.appearanceCount),
        everyElement(3),
      );
    });

    test('third appearance order differs from second appearance order', () {
      for (var seed = 0; seed < 30; seed++) {
        final session = FirstLayerSession(words: words, random: Random(seed));
        final secondOrder = <String>[];
        final thirdOrder = <String>[];
        String? previousWord;

        while (!session.isComplete) {
          final state = session.currentState;
          final currentWord = state.word.word;

          if (state.currentAppearanceNumber == 2) {
            secondOrder.add(currentWord);
          } else if (state.currentAppearanceNumber == 3) {
            thirdOrder.add(currentWord);
          }

          if (previousWord != null) {
            expect(currentWord, isNot(previousWord), reason: 'seed $seed');
          }

          previousWord = currentWord;
          session.answer(StudyChoice.unknown);
        }

        expect(secondOrder, hasLength(words.length));
        expect(thirdOrder, hasLength(words.length));
        expect(
          thirdOrder,
          isNot(orderedEquals(secondOrder)),
          reason: 'seed $seed',
        );
      }
    });
  });
}

FirstLayerSession _session(List<Word> targetWords) {
  return FirstLayerSession(words: targetWords, random: Random(0));
}
