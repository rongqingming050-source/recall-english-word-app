import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../context/context_word_selector.dart';
import '../data/learning_repository.dart';
import '../models/first_layer_word_state.dart';
import '../models/context_article.dart';
import '../models/word.dart';
import 'first_layer_session.dart';

class ContextSessionService {
  const ContextSessionService({
    required this.repository,
    this.wordSelector = const ContextWordSelector(),
  });

  final LearningRepository repository;
  final ContextWordSelector wordSelector;

  Future<ContextSessionData> load(List<Word> targetWords) async {
    final states = await Future.wait(
      targetWords.map((word) async {
        final record = await repository.getRecord(word.id);
        if (record == null || record.firstResult == null) {
          throw StateError('${word.id} 没有可恢复的第一层完成记录。');
        }
        final state = FirstLayerWordState(word: word);
        for (final result in [
          record.firstResult,
          record.secondResult,
          record.thirdResult,
        ]) {
          if (result == null) break;
          state.recordJudgment(result);
        }
        if (!state.isCompleted) {
          throw StateError('${word.id} 的第一层记录不完整。');
        }
        return state;
      }),
    );
    final focusWords = wordSelector.select(states);
    return ContextSessionData(
      focusWords: List.unmodifiable(focusWords),
      focusPriorities: {
        for (final state in states)
          if (focusWords.any((word) => word.id == state.word.id))
            state.word.id: switch (state.firstJudgment) {
              StudyChoice.unknown => ContextWordPriority.unknown,
              StudyChoice.unsure => ContextWordPriority.unsure,
              StudyChoice.known => ContextWordPriority.known,
              null => throw StateError('${state.word.id} 缺少第一层结果。'),
            },
      },
      contextSessionId: _sessionId(targetWords),
      summary: FirstLayerSummary.fromStates(states),
    );
  }

  String _sessionId(List<Word> targetWords) {
    final payload = targetWords.map((word) => word.id).join('|');
    return 'context-${sha256.convert(utf8.encode(payload))}';
  }
}

class ContextSessionData {
  const ContextSessionData({
    required this.focusWords,
    required this.focusPriorities,
    required this.contextSessionId,
    required this.summary,
  });

  final List<Word> focusWords;
  final Map<String, ContextWordPriority> focusPriorities;
  final String contextSessionId;
  final FirstLayerSummary summary;

  ContextArticleRequest get request => ContextArticleRequest(
    contextSessionId: contextSessionId,
    words: focusWords
        .map(
          (word) => ContextArticleWord(
            wordId: word.id,
            word: word.word,
            meaning: word.meaning,
            priority: focusPriorities[word.id]!,
          ),
        )
        .toList(growable: false),
  );
}
