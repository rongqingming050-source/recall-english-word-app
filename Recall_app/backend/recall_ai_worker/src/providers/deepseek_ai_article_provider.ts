import { ServiceError } from "../errors";
import type {
  ContextArticleGenerationRequest,
  ContextArticleGenerationResult,
} from "../types";
import type { AiArticleProvider } from "./ai_article_provider";

const deepSeekChatCompletionsUrl =
  "https://api.deepseek.com/chat/completions";

type Fetcher = typeof fetch;

export class DeepSeekAiArticleProvider implements AiArticleProvider {
  readonly name = "deepseek";

  constructor(
    private readonly apiKey: string,
    private readonly fetcher: Fetcher = fetch,
    private readonly endpoint: string = deepSeekChatCompletionsUrl,
  ) {
    if (!apiKey.trim()) {
      throw new ServiceError(
        "provider_not_configured",
        "Article provider is not configured",
        503,
      );
    }
  }

  async generateContextArticle(
    request: ContextArticleGenerationRequest,
  ): Promise<ContextArticleGenerationResult> {
    let response: Response;
    try {
      response = await this.fetcher.call(globalThis, this.endpoint, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${this.apiKey}`,
        },
        body: JSON.stringify({
          model: request.model,
          messages: [
            {
              role: "system",
              content:
                "You generate Recall context articles. Return only one valid JSON object and no surrounding text.",
            },
            { role: "user", content: request.prompt },
          ],
          response_format: { type: "json_object" },
          thinking: { type: "disabled" },
          stream: false,
          max_tokens: 1200,
        }),
      });
    } catch {
      throw new ServiceError(
        "provider_error",
        "Unable to generate article",
        502,
      );
    }

    if (!response.ok) {
      throw providerHttpError(response.status);
    }

    const payload = await readObject(response);
    const choices = payload.choices;
    if (!Array.isArray(choices) || choices.length === 0) invalidOutput();
    const choice = choices[0];
    if (!isObject(choice) || choice.finish_reason === "length") invalidOutput();
    const message = choice.message;
    if (!isObject(message) || typeof message.content !== "string") {
      invalidOutput();
    }

    let generated: unknown;
    try {
      generated = JSON.parse(message.content);
    } catch {
      invalidOutput();
    }
    if (!isObject(generated)) invalidOutput();
    const title = generated.title;
    const article = generated.article;
    const usedWordIds = generated.usedWordIds;
    if (
      typeof title !== "string" ||
      typeof article !== "string" ||
      !Array.isArray(usedWordIds) ||
      !usedWordIds.every((value): value is string => typeof value === "string")
    ) {
      invalidOutput();
    }
    return { title, article, usedWordIds };
  }
}

async function readObject(response: Response): Promise<Record<string, unknown>> {
  try {
    const payload: unknown = await response.json();
    if (isObject(payload)) return payload;
  } catch {
    // Converted to Recall's stable output error below.
  }
  return invalidOutput();
}

function providerHttpError(status: number): ServiceError {
  if (status === 400 || status === 422) {
    return new ServiceError(
      "provider_invalid_request",
      "Unable to generate article",
      502,
    );
  }
  if (status === 401) {
    return new ServiceError(
      "provider_auth_error",
      "Unable to generate article",
      502,
    );
  }
  if (status === 402) {
    return new ServiceError(
      "provider_payment_required",
      "Unable to generate article",
      503,
    );
  }
  if (status === 403) {
    return new ServiceError(
      "provider_forbidden",
      "Unable to generate article",
      502,
    );
  }
  if (status === 429) {
    return new ServiceError(
      "provider_rate_limited",
      "Unable to generate article",
      503,
    );
  }
  if (status === 500 || status === 503) {
    return new ServiceError(
      "provider_unavailable",
      "Unable to generate article",
      503,
    );
  }
  return new ServiceError(
    `provider_http_${status}`,
    "Unable to generate article",
    502,
  );
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function invalidOutput(): never {
  throw new ServiceError(
    "invalid_model_output",
    "Unable to generate article",
    502,
  );
}
