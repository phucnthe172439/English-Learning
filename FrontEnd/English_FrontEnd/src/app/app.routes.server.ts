import { RenderMode, ServerRoute } from '@angular/ssr';

// Render every page in the browser: the data comes from the API at runtime,
// so there is nothing useful to prerender at build time (and /vocabularies/:id/edit has no fixed ids).
export const serverRoutes: ServerRoute[] = [
  {
    path: '**',
    renderMode: RenderMode.Client
  }
];
