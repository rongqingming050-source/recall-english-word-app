import type { ContextArticleRequest } from "./types";

export const contextArticlePromptVersion = "context_article_v1";

export class ContextArticlePromptBuilder {
  build(request: ContextArticleRequest): string {
    const words = [...request.words].sort(
      (a, b) => priorityRank(a.priority) - priorityRank(b.priority),
    );
    return [
      "Write one natural, coherent English article that provides useful context for the supplied vocabulary.",
      "Natural English is more important than forcing every word into the article.",
      "Prefer unknown words, then unsure words, then known words.",
      "Whenever a supplied word is used, its sense must agree with Recall's authoritative meaning.",
      "Do not add questions, exercises, translations, vocabulary lists, study advice, proficiency judgments, Markdown, HTML, or chat text.",
      "Return only JSON with exactly: title, article, usedWordIds.",
      "usedWordIds must contain only IDs whose word or slash-separated surface form actually appears as a complete English word in article.",
      `Vocabulary: ${JSON.stringify(words)}`,
    ].join("\n");
  }
}

function priorityRank(priority: string): number {
  return priority === "unknown" ? 0 : priority === "unsure" ? 1 : 2;
}
