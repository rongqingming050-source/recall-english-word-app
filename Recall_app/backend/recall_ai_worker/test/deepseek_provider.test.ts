import { describe, expect, it, vi } from "vitest";

import { ServiceError } from "../src/errors";
import worker from "../src/index";
import { DeepSeekAiArticleProvider } from "../src/providers/deepseek_ai_article_provider";
import { createProvider } from "../src/providers/provider_factory";
import type { ContextArticleGenerationRequest } from "../src/types";

const request: ContextArticleGenerationRequest = {
  requestId: "req-deepseek",
  contextSessionId: "session-deepseek",
  words: [
    {
      wordId: "kaoyan:derive",
      word: "derive",
      meaning: "v. 推导出",
      priority: "unknown",
    },
  ],
  prompt: "Return JSON with title, article, and usedWordIds.",
  promptVersion: "context_article_v1",
  model: "deepseek-v4-flash",
};

describe("DeepSeekAiArticleProvider", () => {
  it("satisfies the provider contract and uses DeepSeek JSON Output", async () => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(
      deepSeekResponse({
        title: "Evidence and Insight",
        article: "Researchers derive a conclusion from the evidence.",
        usedWordIds: ["kaoyan:derive"],
      }),
    );
    const provider = new DeepSeekAiArticleProvider(
      "test-deepseek-key",
      fetcher,
    );

    const result = await provider.generateContextArticle(request);

    expect(provider.name).toBe("deepseek");
    expect(result).toEqual({
      title: "Evidence and Insight",
      article: "Researchers derive a conclusion from the evidence.",
      usedWordIds: ["kaoyan:derive"],
    });
    expect(fetcher).toHaveBeenCalledOnce();
    const [url, init] = fetcher.mock.calls[0];
    expect(url).toBe("https://api.deepseek.com/chat/completions");
    expect(init?.method).toBe("POST");
    expect(init?.headers).toMatchObject({
      "content-type": "application/json",
      authorization: "Bearer test-deepseek-key",
    });
    const body = JSON.parse(init?.body as string) as Record<string, unknown>;
    expect(body.model).toBe("deepseek-v4-flash");
    expect(body.response_format).toEqual({ type: "json_object" });
    expect(body.thinking).toEqual({ type: "disabled" });
    expect(body.stream).toBe(false);
    expect(body.max_tokens).toBe(1200);
    expect(JSON.stringify(body)).toContain(request.prompt);
  });

  it.each([
    [400, "provider_invalid_request"],
    [401, "provider_auth_error"],
    [402, "provider_payment_required"],
    [403, "provider_forbidden"],
    [422, "provider_invalid_request"],
    [429, "provider_rate_limited"],
    [500, "provider_unavailable"],
    [503, "provider_unavailable"],
    [404, "provider_http_404"],
  ])("maps DeepSeek HTTP %s to %s", async (status, code) => {
    const fetcher = vi
      .fn<typeof fetch>()
      .mockResolvedValue(
        Response.json({ error: { message: "raw upstream detail" } }, { status }),
      );
    const provider = new DeepSeekAiArticleProvider("test-key", fetcher);

    await expect(provider.generateContextArticle(request)).rejects.toMatchObject(
      {
        code,
        message: "Unable to generate article",
      },
    );
  });

  it.each([
    ["non-JSON message", "not-json", "stop"],
    ["truncated output", '{"title":"cut', "length"],
    ["missing fields", '{"title":"Only a title"}', "stop"],
  ])("rejects %s as invalid_model_output", async (_, content, finishReason) => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(
      Response.json({
        choices: [
          {
            finish_reason: finishReason,
            message: { role: "assistant", content },
          },
        ],
      }),
    );
    const provider = new DeepSeekAiArticleProvider("test-key", fetcher);

    await expect(provider.generateContextArticle(request)).rejects.toMatchObject(
      { code: "invalid_model_output" },
    );
  });

  it("requires only the DeepSeek secret when DeepSeek is selected", () => {
    expect(() =>
      createProvider({
        AI_PROVIDER: "deepseek",
        AI_MODEL: "deepseek-v4-flash",
      }),
    ).toThrow(ServiceError);
    expect(
      createProvider({
        AI_PROVIDER: "deepseek",
        AI_MODEL: "deepseek-v4-flash",
        DEEPSEEK_API_KEY: "test-key",
      }).name,
    ).toBe("deepseek");
  });

  it("runs through the Worker route without exposing the DeepSeek key", async () => {
    const upstream = vi.fn<typeof fetch>().mockResolvedValue(
      deepSeekResponse({
        title: "A Complete Route",
        article: "Researchers derive a conclusion from the evidence.",
        usedWordIds: ["kaoyan:derive"],
      }),
    );
    vi.stubGlobal("fetch", upstream);
    try {
      const response = await worker.fetch(
        new Request("https://recall.test/v1/context-article", {
          method: "POST",
          headers: {
            "content-type": "application/json",
            authorization: "Bearer recall-test-token",
          },
          body: JSON.stringify({
            requestId: request.requestId,
            contextSessionId: request.contextSessionId,
            words: request.words,
          }),
        }),
        {
          AI_PROVIDER: "deepseek",
          AI_MODEL: "deepseek-v4-flash",
          RECALL_APP_TOKEN: "recall-test-token",
          DEEPSEEK_API_KEY: "deepseek-test-key",
        },
      );

      expect(response.status).toBe(200);
      const text = await response.text();
      expect(JSON.parse(text)).toMatchObject({
        provider: "deepseek",
        model: "deepseek-v4-flash",
        title: "A Complete Route",
      });
      expect(text).not.toContain("deepseek-test-key");
    } finally {
      vi.unstubAllGlobals();
    }
  });
});

function deepSeekResponse(result: Record<string, unknown>): Response {
  return Response.json({
    id: "deepseek-response",
    choices: [
      {
        index: 0,
        finish_reason: "stop",
        message: {
          role: "assistant",
          content: JSON.stringify(result),
        },
      },
    ],
    model: "deepseek-v4-flash",
  });
}
