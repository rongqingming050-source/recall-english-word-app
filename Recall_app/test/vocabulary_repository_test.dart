import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recall_app/data/vocabulary_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled formal asset passes its pinned SHA-256', () async {
    final repository = await AssetVocabularyRepository.load();
    expect(repository.totalCount, 5847);
  });

  test('formal vocabulary parses all 5847 validated entries', () async {
    final jsonText = await File(
      AssetVocabularyRepository.assetPath,
    ).readAsString();
    final repository = AssetVocabularyRepository.fromJsonString(jsonText);

    expect(repository.book.id, 'kaoyan_final');
    expect(repository.book.version, 4);
    expect(repository.book.name, '考研英语');
    expect(repository.book.expectedWordCount, 5847);
    expect(repository.words, hasLength(5847));
    expect(repository.words.first.word, 'radiate');
    expect(repository.words.last.word, 'yearning');
    expect(repository.words.map((word) => word.id).toSet(), hasLength(5847));
    expect(
      repository.words.every(
        (word) =>
            word.word.isNotEmpty &&
            word.phonetic.isNotEmpty &&
            word.meaning.isNotEmpty &&
            word.example.isNotEmpty,
      ),
      isTrue,
    );

    final elementary = repository.findById('kaoyan_v1:elementary');
    expect(elementary, isNotNull);
    expect(elementary!.meaning, 'adj. 初等的；基本的；简单的；容易的');
  });

  test(
    'parser reports malformed records instead of silently dropping them',
    () {
      const invalid = '''
      {
        "schemaVersion": 1,
        "book": {
          "id": "kaoyan_v1",
          "name": "考研英语",
          "version": 1,
          "description": "fixture",
          "expectedWordCount": 1,
          "source": "fixture",
          "licenseNote": "fixture"
        },
        "words": [{
          "id": "alpha",
          "position": 1,
          "word": "alpha",
          "phonetic": "/a/",
          "meaning": "",
          "example": "Alpha."
        }]
      }
    ''';

      expect(
        () => AssetVocabularyRepository.fromJsonString(invalid),
        throwsA(
          isA<VocabularyFormatException>().having(
            (error) => error.message,
            'message',
            contains('words[0].meaning'),
          ),
        ),
      );
    },
  );
}
