import { HttpErrorResponse } from '@angular/common/http';
import { API_BASE_URL } from './api.config';

/**
 * Turns an HTTP error from the API into a message a user can read.
 * The API answers errors in two shapes:
 *   - plain text, e.g. 409 "Topic 'Travel' already exists."
 *   - ASP.NET validation problem, e.g. 400 { errors: { Word: ["The Word field is required."] } }
 */
export function apiErrorMessage(error: unknown): string {
  if (!(error instanceof HttpErrorResponse)) {
    return 'Something went wrong.';
  }

  // Status 0 = the request never got an answer (API not running, certificate not trusted, CORS...)
  if (error.status === 0) {
    return `Cannot reach the API at ${API_BASE_URL}. Is the backend running?`;
  }

  // 5xx = a bug or crash on the server: its body may be a stack trace, never show that to users.
  if (error.status >= 500) {
    return 'The server had a problem. Please try again.';
  }

  const body = error.error;
  if (typeof body === 'string' && body.trim()) {
    return body;
  }
  if (body && typeof body === 'object' && body.errors) {
    const messages = Object.values(body.errors as Record<string, string[]>).flat();
    if (messages.length) {
      return messages.join(' ');
    }
  }
  if (error.status === 404) {
    return 'Not found. It may have been deleted.';
  }
  return `Request failed (${error.status}).`;
}
