# Recall AI Worker

Cloudflare Worker for Recall's provider-neutral context article endpoint.

## Local development

1. Copy `.dev.vars.example` to `.dev.vars` and replace the local Recall access token. Also replace `DEEPSEEK_API_KEY` with your DeepSeek key when using the real provider. `.dev.vars` is ignored and must never be committed.
2. Run `npm install`.
3. Run `npx wrangler dev`.
4. Configure the Flutter app with the displayed Worker URL and the same Recall access token.

Implemented providers are `fake` and `deepseek`. The production configuration uses `AI_PROVIDER=deepseek` with `AI_MODEL=deepseek-v4-flash`. `AI_PROVIDER=fake` never calls a paid AI service and should be used for local UI development and automated tests. `DEEPSEEK_API_KEY` belongs only in `.dev.vars` locally or a Cloudflare Worker Secret in deployment.

## Cloudflare secrets

After `npx wrangler login`, enter secrets interactively; do not paste them into source files or command arguments:

```text
npx wrangler secret put DEEPSEEK_API_KEY
npx wrangler secret put RECALL_APP_TOKEN
```

`DEEPSEEK_API_KEY` authenticates Worker → DeepSeek. `RECALL_APP_TOKEN` is a different secret that authenticates Flutter → Worker.

## Verification

Run `npm run typecheck` and `npm test`. `GET /health` never invokes a provider. `POST /v1/context-article` requires `Authorization: Bearer <RECALL_APP_TOKEN>`.

The complete Chinese development, deployment, data, and API documentation is available from [`../../docs/README.md`](../../docs/README.md).
