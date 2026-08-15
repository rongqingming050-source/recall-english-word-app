export const priorities = ["unknown", "unsure", "known"] as const;
export type WordPriority = (typeof priorities)[number];

export interface ContextArticleWord {
  wordId: string;
  word: string;
  meaning: string;
  priority: WordPriority;
}

export interface ContextArticleRequest {
  requestId: string;
  contextSessionId: string;
  words: ContextArticleWord[];
}

export interface ContextArticleGenerationRequest extends ContextArticleRequest {
  prompt: string;
  promptVersion: string;
  model: string;
}

export interface ContextArticleGenerationResult {
  title: string;
  article: string;
  usedWordIds: string[];
}

export interface ContextArticleResponse extends ContextArticleGenerationResult {
  requestId: string;
  contextSessionId: string;
  provider: string;
  model: string;
  promptVersion: string;
  generatedAt: string;
}

export interface Env {
  AI_PROVIDER?: string;
  AI_MODEL?: string;
  RECALL_APP_TOKEN?: string;
  DEEPSEEK_API_KEY?: string;
}
