import type { ContextArticleGenerationRequest, ContextArticleGenerationResult } from "../types";

export interface AiArticleProvider {
  readonly name: string;
  generateContextArticle(request: ContextArticleGenerationRequest): Promise<ContextArticleGenerationResult>;
}
