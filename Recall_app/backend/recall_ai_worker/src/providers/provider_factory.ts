import { ServiceError } from "../errors";
import type { Env } from "../types";
import type { AiArticleProvider } from "./ai_article_provider";
import { FakeAiArticleProvider } from "./fake_ai_article_provider";
import { DeepSeekAiArticleProvider } from "./deepseek_ai_article_provider";

type ProviderFactory = (env: Env) => AiArticleProvider;

const factories: Readonly<Record<string, ProviderFactory>> = {
  fake: () => new FakeAiArticleProvider(),
  deepseek: (env) =>
    new DeepSeekAiArticleProvider(env.DEEPSEEK_API_KEY ?? ""),
};

export function createProvider(env: Env): AiArticleProvider {
  const name = env.AI_PROVIDER?.trim().toLowerCase();
  if (!name || !factories[name]) {
    throw new ServiceError("provider_not_configured", "Article provider is not configured", 503);
  }
  return factories[name](env);
}
