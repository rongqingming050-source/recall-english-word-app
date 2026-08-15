import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../data/context_article_repository.dart';
import '../models/context_article.dart';
import '../settings/ai_service_settings.dart';

abstract interface class ArticleGenerator {
  Future<ArticleGenerationResult> generateArticle(
    ContextArticleRequest request,
  );

  Future<ArticleGenerationResult> regenerateArticle(
    ContextArticleRequest request,
  );

  Future<void> skipArticle(ContextArticleRequest request);
}

class ArticleGenerationResult {
  const ArticleGenerationResult({
    required this.article,
    required this.isCached,
  });

  final ContextArticle article;
  final bool isCached;
}

class ArticleGenerationException implements Exception {
  const ArticleGenerationException(this.code);

  final String code;

  @override
  String toString() => 'ArticleGenerationException($code)';
}

class RemoteArticleGenerator implements ArticleGenerator {
  RemoteArticleGenerator({
    required this.repository,
    required this.settings,
    http.Client? client,
    this.timeout = const Duration(seconds: 70),
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now;

  final ContextArticleRepository repository;
  final AiServiceSettings settings;
  final http.Client _client;
  final Duration timeout;
  final DateTime Function() _now;

  @override
  Future<ArticleGenerationResult> generateArticle(
    ContextArticleRequest request,
  ) => _generateArticle(request, useCache: true);

  @override
  Future<ArticleGenerationResult> regenerateArticle(
    ContextArticleRequest request,
  ) => _generateArticle(request, useCache: false);

  Future<ArticleGenerationResult> _generateArticle(
    ContextArticleRequest request, {
    required bool useCache,
  }) async {
    if (useCache) {
      final cached = await repository.getSuccessfulContextArticle(
        request.contextSessionId,
      );
      if (cached != null) {
        return ArticleGenerationResult(article: cached, isCached: true);
      }
    }

    final requestId = _newRequestId();
    try {
      final configuration = await settings.load();
      final endpoint = _contextArticleEndpoint(configuration);
      final response = await _client
          .post(
            endpoint,
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer ${configuration.accessToken}',
            },
            body: jsonEncode({
              'requestId': requestId,
              'contextSessionId': request.contextSessionId,
              'words': request.words.map((word) => word.toJson()).toList(),
            }),
          )
          .timeout(timeout);
      final body = _decodeObject(response.body);
      if (response.statusCode != 200) {
        throw ArticleGenerationException(_readErrorCode(body));
      }
      final article = _articleFromResponse(body, request, requestId);
      if (!useCache) {
        await repository.deleteContextArticle(request.contextSessionId);
      }
      await repository.upsertContextArticle(article);
      return ArticleGenerationResult(article: article, isCached: false);
    } on ArticleGenerationException catch (error) {
      await _saveFailure(request, requestId, error.code);
      rethrow;
    } on TimeoutException {
      await _saveFailure(request, requestId, 'network_timeout');
      throw const ArticleGenerationException('network_timeout');
    } on Object {
      await _saveFailure(request, requestId, 'network_error');
      throw const ArticleGenerationException('network_error');
    }
  }

  @override
  Future<void> skipArticle(ContextArticleRequest request) async {
    if (await repository.getSuccessfulContextArticle(
          request.contextSessionId,
        ) !=
        null) {
      return;
    }
    await repository.upsertContextArticle(
      ContextArticle(
        contextSessionId: request.contextSessionId,
        requestId: _newRequestId(),
        title: '',
        articleText: '',
        sourceWordIds: request.words.map((word) => word.wordId).toList(),
        usedWordIds: const [],
        provider: '',
        model: '',
        promptVersion: '',
        status: ContextArticleStatus.skipped,
        generatedAt: _now(),
      ),
    );
  }

  Uri _contextArticleEndpoint(AiServiceConfiguration configuration) {
    if (!configuration.isConfigured) {
      throw const ArticleGenerationException('backend_not_configured');
    }
    final base = Uri.tryParse(configuration.backendUrl.trim());
    if (base == null ||
        !base.hasAuthority ||
        (base.scheme != 'https' && base.scheme != 'http')) {
      throw const ArticleGenerationException('backend_not_configured');
    }
    final clean = configuration.backendUrl.trim().replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    return Uri.parse('$clean/v1/context-article');
  }

  Map<String, Object?> _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Converted to the stable invalid response code below.
    }
    throw const ArticleGenerationException('invalid_response');
  }

  String _readErrorCode(Map<String, Object?> body) {
    final error = body['error'];
    if (error is Map && error['code'] is String) {
      return error['code']! as String;
    }
    return 'server_error';
  }

  ContextArticle _articleFromResponse(
    Map<String, Object?> body,
    ContextArticleRequest request,
    String requestId,
  ) {
    final title = body['title'];
    final articleText = body['article'];
    final rawUsedIds = body['usedWordIds'];
    final provider = body['provider'];
    final model = body['model'];
    final promptVersion = body['promptVersion'];
    if (title is! String ||
        title.trim().isEmpty ||
        articleText is! String ||
        articleText.trim().isEmpty ||
        rawUsedIds is! List ||
        provider is! String ||
        model is! String ||
        promptVersion is! String) {
      throw const ArticleGenerationException('invalid_response');
    }
    final usedIds = rawUsedIds.whereType<String>().toList();
    if (usedIds.length != rawUsedIds.length ||
        usedIds.toSet().length != usedIds.length) {
      throw const ArticleGenerationException('invalid_response');
    }
    final byId = {for (final word in request.words) word.wordId: word};
    for (final id in usedIds) {
      final word = byId[id];
      if (word == null ||
          !surfaceForms(
            word.word,
          ).any((surface) => containsWholeWord(articleText, surface))) {
        throw const ArticleGenerationException('invalid_response');
      }
    }
    return ContextArticle(
      contextSessionId: request.contextSessionId,
      requestId: body['requestId'] is String
          ? body['requestId']! as String
          : requestId,
      title: title.trim(),
      articleText: articleText.trim(),
      sourceWordIds: request.words.map((word) => word.wordId).toList(),
      usedWordIds: usedIds,
      provider: provider,
      model: model,
      promptVersion: promptVersion,
      status: ContextArticleStatus.success,
      generatedAt:
          DateTime.tryParse(body['generatedAt'] as String? ?? '') ?? _now(),
    );
  }

  Future<void> _saveFailure(
    ContextArticleRequest request,
    String requestId,
    String code,
  ) => repository.upsertContextArticle(
    ContextArticle(
      contextSessionId: request.contextSessionId,
      requestId: requestId,
      title: '',
      articleText: '',
      sourceWordIds: request.words.map((word) => word.wordId).toList(),
      usedWordIds: const [],
      provider: '',
      model: '',
      promptVersion: '',
      status: ContextArticleStatus.failed,
      generatedAt: _now(),
      errorCode: code,
    ),
  );
}

class FakeArticleGenerator implements ArticleGenerator {
  FakeArticleGenerator({
    this.delay = Duration.zero,
    this.errorCode,
    this.title = 'A Deliberate Change',
  });

  final Duration delay;
  final String? errorCode;
  final String title;
  int generationCount = 0;
  int skipCount = 0;

  @override
  Future<ArticleGenerationResult> generateArticle(
    ContextArticleRequest request,
  ) async {
    generationCount += 1;
    if (delay != Duration.zero) await Future<void>.delayed(delay);
    if (errorCode != null) throw ArticleGenerationException(errorCode!);
    final surfaces = request.words
        .map((word) => surfaceForms(word.word).first)
        .join(', ');
    return ArticleGenerationResult(
      article: ContextArticle(
        contextSessionId: request.contextSessionId,
        requestId: 'fake-request-$generationCount',
        title: title,
        articleText:
            'A careful reader encountered $surfaces in a natural account. '
            'Each idea helped the discussion move toward a practical conclusion.',
        sourceWordIds: request.words.map((word) => word.wordId).toList(),
        usedWordIds: request.words.map((word) => word.wordId).toList(),
        provider: 'fake',
        model: 'fake-context-v1',
        promptVersion: 'context_article_v1',
        status: ContextArticleStatus.success,
        generatedAt: DateTime(2026, 1, 1),
      ),
      isCached: false,
    );
  }

  @override
  Future<ArticleGenerationResult> regenerateArticle(
    ContextArticleRequest request,
  ) => generateArticle(request);

  @override
  Future<void> skipArticle(ContextArticleRequest request) async {
    skipCount += 1;
  }
}

List<String> surfaceForms(String word) => word
    .split('/')
    .map((surface) => surface.trim())
    .where((surface) => surface.isNotEmpty)
    .toList(growable: false);

bool containsWholeWord(String article, String surface) {
  final escaped = RegExp.escape(surface);
  return RegExp(
    '(^|[^A-Za-z])$escaped(?=\$|[^A-Za-z])',
    caseSensitive: false,
  ).hasMatch(article);
}

String _newRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return 'req-$hex';
}
