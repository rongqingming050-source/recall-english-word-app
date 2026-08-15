export type ErrorCode =
  | "unauthorized"
  | "invalid_request"
  | "provider_not_configured"
  | "provider_auth_error"
  | "provider_invalid_request"
  | "provider_payment_required"
  | "provider_forbidden"
  | "provider_unavailable"
  | "provider_rate_limited"
  | "provider_timeout"
  | "provider_error"
  | "invalid_model_output"
  | "server_error"
  | `provider_http_${number}`;

export class ServiceError extends Error {
  constructor(
    readonly code: ErrorCode,
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

export function errorResponse(error: unknown, requestId?: string): Response {
  const safe = error instanceof ServiceError
    ? error
    : new ServiceError("server_error", "Unable to generate article", 500);
  return Response.json(
    {
      error: { code: safe.code, message: safe.message },
      ...(requestId ? { requestId } : {}),
    },
    { status: safe.status },
  );
}
