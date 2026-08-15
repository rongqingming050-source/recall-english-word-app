import { describe, expect, it, vi } from "vitest";

import worker from "../src/index";
import { ContextArticleValidator } from "../src/context_article_validator";
import { ServiceError } from "../src/errors";
import { FakeAiArticleProvider } from "../src/providers/fake_ai_article_provider";
import type { AiArticleProvider } from "../src/providers/ai_article_provider";
import { ContextArticleService } from "../src/service";
import type { ContextArticleGenerationRequest, ContextArticleRequest, Env } from "../src/types";

const env: Env = {
  AI_PROVIDER: "fake",
  AI_MODEL: "fake-context-v1",
  RECALL_APP_TOKEN: "test-recall-token",
};

const validBody: ContextArticleRequest = {
  requestId: "req-123",
  contextSessionId: "session-123",
  words: [
    { wordId: "kaoyan:1", word: "derive", meaning: "v. 推导出", priority: "unknown" },
    { wordId: "kaoyan:2", word: "cosy/cozy", meaning: "adj. 舒适的", priority: "unsure" },
  ],
};

function call(body: unknown = validBody, token: string | null = env.RECALL_APP_TOKEN!): Promise<Response> {
  return worker.fetch(
    new Request("https://recall.test/v1/context-article", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(token === null ? {} : { authorization: `Bearer ${token}` }),
      },
      body: JSON.stringify(body),
    }),
    env,
  );
}

describe("Recall AI Worker", () => {
  it("serves health without authentication or provider calls", async () => {
    const response = await worker.fetch(new Request("https://recall.test/health"), {});
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true, service: "recall-ai", version: "v1" });
  });

  it.each([
    ["missing", null],
    ["wrong", "wrong-token"],
  ])("rejects %s token", async (_, token) => {
    const response = await call(validBody, token);
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: { code: "unauthorized", message: "Unauthorized" } });
  });

  it("accepts a correct token and returns the unified shape", async () => {
    const response = await call();
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      requestId: validBody.requestId,
      contextSessionId: validBody.contextSessionId,
      provider: "fake",
      model: "fake-context-v1",
      promptVersion: "context_article_v1",
      usedWordIds: validBody.words.map((word) => word.wordId),
    });
  });

  it.each([
    ["empty words", { ...validBody, words: [] }],
    ["missing wordId", { ...validBody, words: [{ word: "derive", meaning: "推导", priority: "unknown" }] }],
    ["missing word", { ...validBody, words: [{ wordId: "x", meaning: "推导", priority: "unknown" }] }],
    ["missing meaning", { ...validBody, words: [{ wordId: "x", word: "derive", priority: "unknown" }] }],
    ["invalid priority", { ...validBody, words: [{ wordId: "x", word: "derive", meaning: "推导", priority: "hard" }] }],
    ["duplicate wordId", { ...validBody, words: [validBody.words[0], validBody.words[0]] }],
    ["too many words", { ...validBody, words: Array.from({ length: 16 }, (_, index) => ({ wordId: `x-${index}`, word: `word${index}`, meaning: "释义", priority: "known" })) }],
  ])("rejects %s", async (_, body) => {
    const response = await call(body);
    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({ error: { code: "invalid_request" } });
  });

  it("does not leak secrets in error responses", async () => {
    const response = await call({ ...validBody, words: [] });
    const text = await response.text();
    expect(text).not.toContain(env.RECALL_APP_TOKEN!);
    expect(text).not.toContain("Authorization");
    expect(text).not.toContain("Bearer");
  });
});

describe("provider contract and service failures", () => {
  it("FakeAiArticleProvider satisfies the provider contract", async () => {
    const provider: AiArticleProvider = new FakeAiArticleProvider();
    const result = await provider.generateContextArticle(generationRequest());
    expect(result.title).not.toBe("");
    expect(result.article).toContain("derive");
    expect(result.usedWordIds).toEqual(["kaoyan:1", "kaoyan:2"]);
  });

  it("maps provider errors", async () => {
    const provider: AiArticleProvider = {
      name: "throwing",
      generateContextArticle: vi.fn().mockRejectedValue(new Error("secret upstream detail")),
    };
    await expect(new ContextArticleService(provider, "model").generate(validBody)).rejects.toMatchObject({
      code: "provider_error",
    });
  });

  it("maps provider timeout", async () => {
    const provider: AiArticleProvider = {
      name: "slow",
      generateContextArticle: () => new Promise(() => {}),
    };
    await expect(new ContextArticleService(provider, "model", 1).generate(validBody)).rejects.toMatchObject({
      code: "provider_timeout",
    });
  });

  it.each([
    ["unknown ID", { title: "Title", article: "derive", usedWordIds: ["unknown"] }],
    ["empty article", { title: "Title", article: "", usedWordIds: [] }],
    ["empty title", { title: "", article: "derive", usedWordIds: ["kaoyan:1"] }],
    ["claimed word absent", { title: "Title", article: "an article", usedWordIds: ["kaoyan:1"] }],
    ["substring match", { title: "Title", article: "an artful article", usedWordIds: ["art"] }],
  ])("rejects %s model output", (_, result) => {
    const words = result.usedWordIds[0] === "art"
      ? [{ wordId: "art", word: "art", meaning: "艺术", priority: "known" as const }]
      : validBody.words;
    expect(() => new ContextArticleValidator().validate(result, words)).toThrow(ServiceError);
  });

  it("accepts slash-separated surface forms", () => {
    expect(new ContextArticleValidator().validate(
      { title: "Warm Room", article: "The room felt cozy.", usedWordIds: ["kaoyan:2"] },
      validBody.words,
    ).usedWordIds).toEqual(["kaoyan:2"]);
  });
});

function generationRequest(): ContextArticleGenerationRequest {
  return {
    ...validBody,
    prompt: "prompt",
    promptVersion: "context_article_v1",
    model: "fake-context-v1",
  };
}
