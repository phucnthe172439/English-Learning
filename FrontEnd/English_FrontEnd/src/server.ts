import {
  AngularNodeAppEngine,
  createNodeRequestHandler,
  isMainModule,
  writeResponseToNodeResponse,
} from '@angular/ssr/node';
import express from 'express';
import { request as httpRequest } from 'node:http';
import { join } from 'node:path';

const browserDistFolder = join(import.meta.dirname, '../browser');

const app = express();
const angularApp = new AngularNodeAppEngine();

/**
 * Health check for the AWS load balancer. Answered here, before Angular, because the ALB calls the task
 * by its private IP and Angular's SSR host check (NG_ALLOWED_HOSTS) rejects that Host header with 400.
 */
app.get('/healthz', (_req, res) => {
  res.status(200).send('ok');
});

/**
 * Forward /api/* to the API, so the browser only ever talks to this server (no CORS, no hardcoded API host).
 *   docker compose: API_URL=http://api:8080
 *   ng serve:       default http://localhost:5048
 * On AWS ECS the load balancer routes /api/* to the API service before it reaches here.
 */
const apiTarget = new URL(process.env['API_URL'] ?? 'http://localhost:5048');

app.use('/api', (req, res) => {
  const upstream = httpRequest(
    {
      hostname: apiTarget.hostname,
      port: apiTarget.port,
      path: req.originalUrl, // still starts with /api
      method: req.method,
      headers: { ...req.headers, host: apiTarget.host },
    },
    (apiRes) => {
      res.writeHead(apiRes.statusCode ?? 502, apiRes.headers);
      apiRes.pipe(res);
    },
  );
  upstream.on('error', (error) => {
    console.error(`API proxy error: ${error.message}`);
    if (!res.headersSent) {
      res.status(502).json({ message: 'API is unavailable' });
    } else {
      res.end();
    }
  });
  req.pipe(upstream);
});

/**
 * Serve static files from /browser
 */
app.use(
  express.static(browserDistFolder, {
    maxAge: '1y',
    index: false,
    redirect: false,
  }),
);

/**
 * Handle all other requests by rendering the Angular application.
 */
app.use((req, res, next) => {
  angularApp
    .handle(req)
    .then((response) =>
      response ? writeResponseToNodeResponse(response, res) : next(),
    )
    .catch(next);
});

/**
 * Start the server if this module is the main entry point, or it is ran via PM2.
 * The server listens on the port defined by the `PORT` environment variable, or defaults to 4000.
 */
if (isMainModule(import.meta.url) || process.env['pm_id']) {
  const port = process.env['PORT'] || 4000;
  app.listen(port, (error) => {
    if (error) {
      throw error;
    }

    console.log(`Node Express server listening on http://localhost:${port}`);
  });
}

/**
 * Request handler used by the Angular CLI (for dev-server and during build) or Firebase Cloud Functions.
 */
export const reqHandler = createNodeRequestHandler(app);
