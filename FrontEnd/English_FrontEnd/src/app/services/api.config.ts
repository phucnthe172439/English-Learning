/**
 * Base URL of the Learning_EngLish API.
 * Relative, so the app calls the API on the same address it was loaded from:
 *   AWS ECS:          the load balancer sends /api/* to the API service.
 *   Docker / ng serve: the SSR server (src/server.ts) forwards /api/* to API_URL (default http://localhost:5048).
 * During server-side rendering Angular resolves the relative URL against the incoming request's address.
 */
export const API_BASE_URL = '/api';
