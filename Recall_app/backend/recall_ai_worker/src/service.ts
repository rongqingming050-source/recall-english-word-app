import { ServiceError } from "./errors";
import { ContextArticlePromptBuilder, contextArticlePromptVersion } from "./prompt_builder";
import { ContextArticleValidator } from "./context_article_validator";
import type { AiArticleProvider } from "./providers/ai_article_provider";
import type { ContextArticleRequest, ContextArticleResponse } from "./types";

export class ContextArticleService {
  constructor(
    private readonly provider: AiArticleProvider,
    private readonly model: string,
    private readonly timeoutMilliseconds = 60_000,
    private readonly promptBuilder = new ContextArticlePromptBuilder(),
    private readonly validator = new ContextArticleValidator(),
  ) {}

  async generate(request: ContextArticleRequest): Promise<ContextArticleResponse> {
    if (!this.model.trim()) {
      throw new ServiceError("provider_not_configured", "Article provider is not configured", 503);
    }
    const providerCall = this.provider.generateContextArticle({
      ...request,
      prompt: this.promptBuilder.build(request),
      promptVersion: contextArticlePromptVersion,
      model: this.model,
    });
    let result;
    try {
      result = await withTimeout(providerCall, this.timeoutMilliseconds);
    } catch (error) {
      if (error instanceof ServiceError) throw error;
      throw new ServiceError("provider_error", "Unable to generate article", 502);
    }
    const valid = this.validator.validate(result, request.words);
    return {
      ...valid,
      requestId: request.requestId,
      contextSessionId: request.contextSessionId,
      provider: this.provider.name,
      model: this.model,
      promptVersion: contextArticlePromptVersion,
      generatedAt: new Date().toISOString(),
    };
  }
}

async function withTimeout<T>(promise: Promise<T>, milliseconds: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(
      () => reject(new ServiceError("provider_timeout", "Unable to generate article", 504)),
      milliseconds,
    );
  });
  try {
    return await Promise.race([promise, timeout]);
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}
