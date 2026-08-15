import { errorResponse, ServiceError } from "./errors";
import { validateContextArticleRequest } from "./input_validator";
import { createProvider } from "./providers/provider_factory";
import { ContextArticleService } from "./service";
import type { Env } from "./types";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/health") {
      return Response.json({ ok: true, service: "recall-ai", version: "v1" });
    }
    if (request.method !== "POST" || url.pathname !== "/v1/context-article") {
      return Response.json({ error: { code: "invalid_request", message: "Not found" } }, { status: 404 });
    }

    let requestId: string | undefined;
    const startedAt = Date.now();
    try {
      authorize(request, env);
      const parsed = validateContextArticleRequest(await readJson(request));
      requestId = parsed.requestId;
      const provider = createProvider(env);
      const response = await new ContextArticleService(provider, env.AI_MODEL ?? "").generate(parsed);
      console.log(JSON.stringify({
        requestId,
        contextSessionId: parsed.contextSessionId,
        durationMs: Date.now() - startedAt,
        wordCount: parsed.words.length,
        provider: response.provider,
        model: response.model,
        httpStatus: 200,
        result: "success",
      }));
      return Response.json(response);
    } catch (error) {
      const response = errorResponse(error, requestId);
      console.log(JSON.stringify({
        ...(requestId ? { requestId } : {}),
        durationMs: Date.now() - startedAt,
        httpStatus: response.status,
        result: error instanceof ServiceError ? error.code : "server_error",
      }));
      return response;
    }
  },
};

function authorize(request: Request, env: Env): void {
  const expected = env.RECALL_APP_TOKEN;
  const authorization = request.headers.get("Authorization");
  if (!expected || authorization !== `Bearer ${expected}`) {
    throw new ServiceError("unauthorized", "Unauthorized", 401);
  }
}

async function readJson(request: Request): Promise<unknown> {
  try {
    return await request.json();
  } catch {
    throw new ServiceError("invalid_request", "Invalid context article request", 400);
  }
}
