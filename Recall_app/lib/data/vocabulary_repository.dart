import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../models/word.dart';
import 'word_catalog.dart';

class VocabularyBook {
  const VocabularyBook({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.expectedWordCount,
    required this.source,
    required this.licenseNote,
  });

  final String id;
  final String name;
  final int version;
  final String description;
  final int expectedWordCount;
  final String source;
  final String licenseNote;
}

abstract interface class VocabularyRepository implements WordCatalog {
  VocabularyBook get book;

  List<Word> get words;

  int get totalCount => words.length;
}

class AssetVocabularyRepository implements VocabularyRepository {
  AssetVocabularyRepository._({required this.book, required this.words})
    : _wordsById = {for (final word in words) word.id: word};

  static const assetPath = 'assets/vocabulary/kaoyan_clean.json';
  static const formalWordIdNamespace = 'kaoyan_v1';
  static const expectedSha256 =
      'd3a817ddb2d272a22ce51269096f65108b4e360ddeaec5352318dfff182646d1';

  @override
  final VocabularyBook book;

  @override
  final List<WordEntry> words;

  final Map<String, WordEntry> _wordsById;

  static Future<AssetVocabularyRepository> load({AssetBundle? bundle}) async {
    final byteData = await (bundle ?? rootBundle).load(assetPath);
    final bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    final actualSha256 = sha256.convert(bytes).toString();
    if (actualSha256 != expectedSha256) {
      throw VocabularyFormatException(
        '正式词库 SHA-256 不匹配：期望 $expectedSha256，实际 $actualSha256。',
      );
    }
    final jsonText = utf8.decode(bytes);
    return fromJsonString(jsonText);
  }

  static AssetVocabularyRepository fromJsonString(String jsonText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (error) {
      throw VocabularyFormatException('JSON 无法解析：${error.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const VocabularyFormatException('根节点必须是 JSON 对象。');
    }
    _expectExactKeys(decoded, const {'schemaVersion', 'book', 'words'}, '根节点');
    if (decoded['schemaVersion'] != 1) {
      throw VocabularyFormatException(
        '不支持的 schemaVersion：${decoded['schemaVersion']}。',
      );
    }
    final bookJson = _asMap(decoded['book'], 'book');
    _expectExactKeys(bookJson, const {
      'id',
      'name',
      'version',
      'description',
      'expectedWordCount',
      'source',
      'licenseNote',
    }, 'book');
    final book = VocabularyBook(
      id: _requiredString(bookJson, 'id', 'book'),
      name: _requiredString(bookJson, 'name', 'book'),
      version: _requiredPositiveInt(bookJson, 'version', 'book'),
      description: _requiredString(bookJson, 'description', 'book'),
      expectedWordCount: _requiredPositiveInt(
        bookJson,
        'expectedWordCount',
        'book',
      ),
      source: _requiredString(bookJson, 'source', 'book'),
      licenseNote: _requiredString(bookJson, 'licenseNote', 'book'),
    );
    final rawWords = decoded['words'];
    if (rawWords is! List<dynamic>) {
      throw const VocabularyFormatException('words 必须是数组。');
    }
    if (rawWords.length != book.expectedWordCount) {
      throw VocabularyFormatException(
        'expectedWordCount=${book.expectedWordCount}，实际=${rawWords.length}。',
      );
    }

    final entries = <WordEntry>[];
    final sourceIds = <String>{};
    final normalizedWords = <String>{};
    for (var index = 0; index < rawWords.length; index++) {
      final location = 'words[$index]';
      final raw = _asMap(rawWords[index], location);
      _expectExactKeys(raw, const {
        'id',
        'position',
        'word',
        'phonetic',
        'meaning',
        'example',
      }, location);
      final sourceId = _requiredString(raw, 'id', location);
      final position = _requiredPositiveInt(raw, 'position', location);
      final word = _requiredString(raw, 'word', location);
      final phonetic = _requiredString(raw, 'phonetic', location);
      final meaning = _requiredString(raw, 'meaning', location);
      final example = _requiredString(raw, 'example', location);
      if (position != index + 1) {
        throw VocabularyFormatException(
          '$location position=$position，应为 ${index + 1}。',
        );
      }
      if (sourceId != normalizedWordKey(word)) {
        throw VocabularyFormatException(
          '$location id=$sourceId 与规范化 word=${normalizedWordKey(word)} 不一致。',
        );
      }
      if (!sourceIds.add(sourceId)) {
        throw VocabularyFormatException('$location 出现重复 id：$sourceId。');
      }
      if (!normalizedWords.add(normalizedWordKey(word))) {
        throw VocabularyFormatException('$location 出现重复 word：$word。');
      }
      entries.add(
        WordEntry(
          vocabularyId: formalWordIdNamespace,
          sourceId: sourceId,
          position: position,
          word: word,
          phonetic: phonetic,
          meaning: meaning,
          example: example,
        ),
      );
    }
    return AssetVocabularyRepository._(
      book: book,
      words: List.unmodifiable(entries),
    );
  }

  @override
  int get totalCount => words.length;

  @override
  WordEntry? findById(String wordId) => _wordsById[wordId];
}

class ListVocabularyRepository implements VocabularyRepository {
  ListVocabularyRepository(
    Iterable<Word> words, {
    String id = 'fixture',
    String name = '测试词库',
  }) : words = List.unmodifiable(words),
       book = VocabularyBook(
         id: id,
         name: name,
         version: 1,
         description: '自动化测试专用小型词库',
         expectedWordCount: words.length,
         source: 'test fixture',
         licenseNote: 'test only',
       ) {
    _wordsById = {for (final word in this.words) word.id: word};
  }

  @override
  final VocabularyBook book;

  @override
  final List<Word> words;

  late final Map<String, Word> _wordsById;

  @override
  int get totalCount => words.length;

  @override
  Word? findById(String wordId) => _wordsById[wordId];
}

class VocabularyFormatException implements Exception {
  const VocabularyFormatException(this.message);

  final String message;

  @override
  String toString() => 'VocabularyFormatException: $message';
}

Map<String, dynamic> _asMap(Object? value, String location) {
  if (value is Map<String, dynamic>) return value;
  throw VocabularyFormatException('$location 必须是 JSON 对象。');
}

String _requiredString(Map<String, dynamic> map, String key, String location) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  throw VocabularyFormatException('$location.$key 必须是非空字符串。');
}

int _requiredPositiveInt(
  Map<String, dynamic> map,
  String key,
  String location,
) {
  final value = map[key];
  if (value is int && value > 0) return value;
  throw VocabularyFormatException('$location.$key 必须是正整数。');
}

void _expectExactKeys(
  Map<String, dynamic> map,
  Set<String> expected,
  String location,
) {
  final actual = map.keys.toSet();
  if (actual.length == expected.length && actual.containsAll(expected)) return;
  final missing = expected.difference(actual).join(', ');
  final extra = actual.difference(expected).join(', ');
  throw VocabularyFormatException(
    '$location 字段不符合格式；缺少：${missing.isEmpty ? '无' : missing}；'
    '多出：${extra.isEmpty ? '无' : extra}。',
  );
}
