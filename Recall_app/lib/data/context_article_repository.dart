import '../models/context_article.dart';

abstract interface class ContextArticleRepository {
  Future<ContextArticle?> getSuccessfulContextArticle(String contextSessionId);

  Future<void> upsertContextArticle(ContextArticle article);

  Future<void> deleteContextArticle(String contextSessionId);

  Future<List<ContextArticle>> getAllContextArticles();
}
