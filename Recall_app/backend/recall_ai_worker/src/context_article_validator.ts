import { ServiceError } from "./errors";
import type { ContextArticleGenerationResult, ContextArticleWord } from "./types";

export class ContextArticleValidator {
  validate(result: ContextArticleGenerationResult, words: ContextArticleWord[]): ContextArticleGenerationResult {
    if (!result.title?.trim() || !result.article?.trim() || !Array.isArray(result.usedWordIds)) invalid();
    const byId = new Map(words.map((word) => [word.wordId, word]));
    if (new Set(result.usedWordIds).size !== result.usedWordIds.length) invalid();
    for (const id of result.usedWordIds) {
      const word = byId.get(id);
      if (!word || !surfaceForms(word.word).some((form) => containsWholeWord(result.article, form))) invalid();
    }
    return {
      title: result.title.trim(),
      article: result.article.trim(),
      usedWordIds: [...result.usedWordIds],
    };
  }
}

export function surfaceForms(word: string): string[] {
  return word.split("/").map((form) => form.trim()).filter(Boolean);
}

export function containsWholeWord(article: string, surface: string): boolean {
  const escaped = surface.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`(^|[^A-Za-z])${escaped}(?=$|[^A-Za-z])`, "i").test(article);
}

function invalid(): never {
  throw new ServiceError("invalid_model_output", "Unable to generate article", 502);
}
