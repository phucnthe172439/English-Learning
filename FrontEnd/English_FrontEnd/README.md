# English Vocabulary: Frontend

Angular 22 app for the **English-Learning** project. Users browse, search, filter, add, edit and delete English words with their Vietnamese meaning, and see simple statistics. All data comes from the backend API (`WFMTTC_API/Learning_EngLish`).

| | |
|---|---|
| Framework | Angular 22, standalone components, signals, RxJS |
| Forms | Reactive Forms |
| Server | Angular SSR (Node + Express) on port 4000 |
| Tests | Vitest (`npm test`) |
| Full docs | [docs/02-frontend.md](../../docs/02-frontend.md) |

## Screens

| Screen | URL | Features |
|---|---|---|
| Dashboard | `/` | Stats, word list, live search, filter by topic and word type, "Words by topic" chart, edit and delete |
| Add word | `/vocabularies/new` | Word, meaning, word type, topic |
| Edit word | `/vocabularies/:id/edit` | Same form, pre-filled |

---

## Run it

The frontend needs the **API running at `http://localhost:5048`**. Pick one option.

### Option A: everything in Docker (easiest)

Needs only **Docker Desktop**. From the repo root:

```powershell
cd C:\Mini-Project\WFMTTC\English-Learning
Copy-Item .env.example .env      # then set the passwords in .env
docker compose up -d --build
```

| URL | What |
|---|---|
| http://localhost:4000 | This app |
| http://localhost:5048/swagger | API |

This starts SQL Server, creates the database, then starts the API and this app. See [docs/04-database-docker.md](../../docs/04-database-docker.md).

### Option B: frontend on your PC (for development)

Needs **Node.js 24** (the same version as the Docker image) and the API running, either in Docker (`docker compose up -d api`) or from Visual Studio.

```powershell
cd C:\Mini-Project\WFMTTC\English-Learning\FrontEnd\English_FrontEnd
npm ci          # first time, or after package-lock.json changes
npm start       # = ng serve
```

Open http://localhost:4200. The page reloads automatically when you save a file.

---

## Commands

| Command | What it does |
|---|---|
| `npm start` | Dev server on http://localhost:4200 with live reload |
| `npm run build` | Production build into `dist/English_FrontEnd/` (`browser/` + `server/`) |
| `npm run serve:ssr:English_FrontEnd` | Runs the built SSR server on http://localhost:4000 (run `npm run build` first) |
| `npm run watch` | Rebuilds on every change (development build) |
| `npm test` | Unit tests with Vitest |

## Configuration

| Setting | Where | Default | Notes |
|---|---|---|---|
| API address | `src/app/services/api.config.ts` → `API_BASE_URL` | `http://localhost:5048/api` | Compiled into the app, so **rebuild after changing it** |
| SSR server port | `PORT` environment variable | `4000` | |
| Allowed host names (SSR) | `angular.json` → `allowedHosts`, or the `NG_ALLOWED_HOSTS` environment variable | `localhost` | Requests with any other `Host` header are rejected |
| CORS on the API side | `WFMTTC_API/Learning_EngLish/Program.cs` | allows `localhost:4200` and `localhost:4000` | Add your origin there if you serve the app elsewhere |

## Docker image (this folder only)

```powershell
docker build -t english-frontend .
docker run -d --name english-frontend -p 4000:4000 english-frontend
```

The [Dockerfile](Dockerfile) has two stages: `node:24-alpine` runs `npm ci` + `ng build`, then a clean `node:24-alpine` with only the runtime packages runs `server.mjs`. See [docs/03-docker.md](../../docs/03-docker.md).

## Project structure

```
src/
├── main.ts, main.server.ts, server.ts   browser / SSR entry points, Express server
└── app/
    ├── app.ts, app.html, app.routes.ts  shell (top bar) and routes
    ├── pages/
    │   ├── dashboard/                   word list, stats, search, filters, chart
    │   └── vocabulary-form/             add + edit form
    ├── components/
    │   ├── confirm-dialog/              "Are you sure?" dialog
    │   └── toast-container/             success/error messages
    └── services/
        ├── api.config.ts                API base URL
        ├── vocabulary.ts, lookup.ts     HTTP calls (words; topics and word types)
        ├── api-error.ts                 turns HTTP errors into readable messages
        └── confirm.ts, toast.ts         UI helpers
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| Dashboard: "Cannot reach the API at …" | Is http://localhost:5048/swagger reachable? If not, start the API. If yes, press F12 → Console: a CORS error means your origin is missing in the API's `Program.cs` |
| `Header "host" with value "..." is not allowed` | Add the host to `allowedHosts` in `angular.json` (or set `NG_ALLOWED_HOSTS`) and rebuild |
| `npm ci` fails | `package-lock.json` is out of sync: run `npm install` and commit the lock file |
| Port 4200 / 4000 already in use | Stop the other process or container (`docker compose stop frontend`), or use `ng serve --port 4300` (then also allow that origin in the API's CORS) |
