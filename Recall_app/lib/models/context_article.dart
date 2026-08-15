enum ContextArticleStatus { success, failed, skipped }

enum ContextWordPriority { unknown, unsure, known }

class ContextArticleWord {
  const ContextArticleWord({
    required this.wordId,
    required this.word,
    required this.meaning,
    required this.priority,
  });

  final String wordId;
  final String word;
  final String meaning;
  final ContextWordPriority priority;

  Map<String, Object?> toJson() => {
    'wordId': wordId,
    'word': word,
    'meaning': meaning,
    'priority': priority.name,
  };
}

class ContextArticleRequest {
  const ContextArticleRequest({
    required this.contextSessionId,
    required this.words,
  });

  final String contextSessionId;
  final List<ContextArticleWord> words;
}

class ContextArticle {
  const ContextArticle({
    required this.contextSessionId,
    required this.requestId,
    required this.title,
    required this.articleText,
    required this.sourceWordIds,
    required this.usedWordIds,
    required this.provider,
    required this.model,
    required this.promptVersion,
    required this.status,
    required this.generatedAt,
    this.errorCode,
    this.id,
  });

  final int? id;
  final String contextSessionId;
  final String requestId;
  final String title;
  final String articleText;
  final List<String> sourceWordIds;
  final List<String> usedWordIds;
  final String provider;
  final String model;
  final String promptVersion;
  final ContextArticleStatus status;
  final DateTime generatedAt;
  final String? errorCode;

  Map<String, Object?> toExportJson() => {
    'contextSessionId': contextSessionId,
    'title': title,
    'sourceWordIds': sourceWordIds,
    'usedWordIds': usedWordIds,
    'provider': provider,
    'model': model,
    'promptVersion': promptVersion,
    'status': status.name,
    'generatedAt': generatedAt.toIso8601String(),
    'errorCode': errorCode,
  };
}
