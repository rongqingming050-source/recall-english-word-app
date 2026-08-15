import type { AiArticleProvider } from "./ai_article_provider";
import type { ContextArticleGenerationRequest, ContextArticleGenerationResult } from "../types";

export class FakeAiArticleProvider implements AiArticleProvider {
  readonly name = "fake";

  async generateContextArticle(request: ContextArticleGenerationRequest): Promise<ContextArticleGenerationResult> {
    const ordered = [...request.words].sort((a, b) => rank(a.priority) - rank(b.priority));
    const selected = ordered.slice(0, Math.min(ordered.length, 10));
    const surfaces = selected.map((item) => item.word.split("/")[0].trim());
    return {
      title: "A Deliberate Change",
      article: `A small research team faced an unfamiliar problem. During a careful discussion, they used ${joinNaturally(surfaces)} while shaping a practical response. Their final account connected each idea naturally and gave the team a clearer direction.`,
      usedWordIds: selected.map((item) => item.wordId),
    };
  }
}

function rank(priority: string): number {
  return priority === "unknown" ? 0 : priority === "unsure" ? 1 : 2;
}

function joinNaturally(words: string[]): string {
  if (words.length === 1) return words[0];
  if (words.length === 2) return `${words[0]} and ${words[1]}`;
  return `${words.slice(0, -1).join(", ")}, and ${words.at(-1)}`;
}
