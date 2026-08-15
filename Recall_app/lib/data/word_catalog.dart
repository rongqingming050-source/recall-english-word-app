import '../models/word.dart';

abstract interface class WordCatalog {
  Word? findById(String wordId);
}

class ListWordCatalog implements WordCatalog {
  ListWordCatalog(Iterable<Word> words)
    : _wordsById = {for (final word in words) word.id: word};

  final Map<String, Word> _wordsById;

  @override
  Word? findById(String wordId) => _wordsById[wordId];
}
