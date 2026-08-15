class Word {
  const Word({
    required this.word,
    required this.phonetic,
    required this.meaning,
    required this.example,
  });

  String get id => normalizedWordKey(word);

  final String word;
  final String phonetic;
  final String meaning;
  final String example;
}

class WordEntry extends Word {
  const WordEntry({
    required this.sourceId,
    required this.position,
    required super.word,
    required super.phonetic,
    required super.meaning,
    required super.example,
    this.vocabularyId = 'kaoyan_v1',
  });

  final String vocabularyId;
  final String sourceId;
  final int position;

  @override
  String get id => '$vocabularyId:$sourceId';
}

String normalizedWordKey(String word) => word.trim().toLowerCase();
