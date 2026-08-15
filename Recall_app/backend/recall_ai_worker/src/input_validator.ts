import { ServiceError } from "./errors";
import { priorities, type ContextArticleRequest, type ContextArticleWord } from "./types";

export const maximumWordCount = 15;
const identifierPattern = /^[A-Za-z0-9][A-Za-z0-9:._-]{0,127}$/;

export function validateContextArticleRequest(value: unknown): ContextArticleRequest {
  if (!isObject(value)) invalid();
  const requestId = requiredIdentifier(value.requestId);
  const contextSessionId = requiredIdentifier(value.contextSessionId);
  if (!Array.isArray(value.words) || value.words.length === 0 || value.words.length > maximumWordCount) {
    invalid();
  }
  const words = value.words.map(validateWord);
  if (new Set(words.map((word) => word.wordId)).size !== words.length) invalid();
  return { requestId, contextSessionId, words };
}

function validateWord(value: unknown): ContextArticleWord {
  if (!isObject(value)) invalid();
  const wordId = requiredIdentifier(value.wordId);
  const word = requiredText(value.word, 100);
  const meaning = requiredText(value.meaning, 500);
  if (typeof value.priority !== "string" || !priorities.includes(value.priority as never)) invalid();
  return { wordId, word, meaning, priority: value.priority as ContextArticleWord["priority"] };
}

function requiredIdentifier(value: unknown): string {
  if (typeof value !== "string" || !identifierPattern.test(value)) invalid();
  return value;
}

function requiredText(value: unknown, maximumLength: number): string {
  if (typeof value !== "string") invalid();
  const text = value.trim();
  if (text.length === 0 || text.length > maximumLength) invalid();
  return text;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function invalid(): never {
  throw new ServiceError("invalid_request", "Invalid context article request", 400);
}
