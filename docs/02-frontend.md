# 02 · Frontend (`FrontEnd/English_FrontEnd`)

The frontend is an **Angular 22** single-page app. Users can **browse, search, filter, add, edit and delete English vocabulary**, and see simple statistics. All data comes from the backend API (see `01-api.md`).

- **Framework:** Angular 22, standalone components, **signals** for state, RxJS for HTTP
- **Forms:** Reactive Forms
- **Server:** Angular SSR (Node + Express) serves the app, but every page renders in the browser (see section 6)
- **Tests:** Vitest (`npm test`)

---

## 1. What users can do

| Screen | URL | Features |
|---|---|---|
| **Dashboard** | `/` | Summary stats · word list · live search · filter by topic and word type · "Words by topic" bar chart · edit and delete buttons |
| **Add word** | `/vocabularies/new` | Form: word, meaning, word type, topic |
| **Edit word** | `/vocabularies/:id/edit` | Same form, pre-filled with the existing word |
| Any other URL | `/**` | Redirects to `/` |

### Dashboard in detail

```
┌──────────────────────────────────────────────────────────────────────┐
│ Aa English Vocabulary                        Dashboard   Add word    │  ← top bar (app.html)
├──────────────────────────────────────────────────────────────────────┤
│ ┌─────────────┐ ┌─────────────────┐ ┌─────────────┐                  │
│ │ Total words │ │ Topics in use   │ │ Word types  │                  │  ← stats
│ │     120     │ │     6 / 8       │ │      5      │                  │
│ └─────────────┘ └─────────────────┘ └─────────────┘                  │
│ ┌──────────────────────────────────────────┐ ┌─────────────────────┐ │
│ │ [Search word or meaning…] [Topic▾][Type▾]│ │ Words by topic      │ │
│ │──────────────────────────────────────────│ │ Food    ██████ 25   │ │  ← click a bar to
│ │ Word    Meaning    Type    Topic         │ │ Travel  ████   18   │ │    filter by topic
│ │ apple   quả táo    noun    Food  ✎ 🗑    │ │ Work    ██     9    │ │
│ │ ...                                      │ │                     │ │
│ └──────────────────────────────────────────┘ └─────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

- **Total words**: sum of `vocabularyCount` over all topics.
- **Topics in use**: topics that have at least one word, out of all topics.
- **Search**: matches the word **or** its meaning. The request is sent **250 ms after you stop typing** (debounce), and any older request still in flight is cancelled (`switchMap`).
- **Filters**: topic and word-type dropdowns. **Clear** resets all filters.
- **Bar chart**: clicking a topic filters the table to that topic, and clicking it again removes the filter.
- **Delete**: asks for confirmation in a dialog, then removes the row, refreshes the counts and shows a toast.
- **States**: "Loading words…", an error box with **Try again**, and an empty state with **Clear filters**.

### Add / Edit form

- One component (`VocabularyForm`) serves both routes. If the URL has an `:id`, it's in **edit** mode.
- Validation matches the API rules:

  | Field | Rule |
  |---|---|
  | Word | Required, not only spaces, max 100 |
  | Meaning | Required, not only spaces, max 500 |
  | Word type | Must be selected |
  | Topic | Must be selected |

- Errors appear only after a field is touched or after you click save.
- On success: a toast ("Added …" / "Updated …") and a redirect to the dashboard.
- On an API error (for example a duplicate word): an error toast, and you stay on the form.
- If the word can't be loaded (for example a 404): an error toast and a redirect to the dashboard.

---

## 2. Folder structure

```
FrontEnd/English_FrontEnd/
├── angular.json            Build config (output, SSR, allowedHosts, budgets)
├── package.json            Dependencies + npm scripts
├── Dockerfile / .dockerignore   (see 03-docker.md)
├── public/                 Static files copied as-is (favicon…)
└── src/
    ├── index.html
    ├── main.ts             Browser entry point
    ├── main.server.ts      Server (SSR) entry point
    ├── server.ts           Express server: serves static files + Angular
    ├── styles.css          Global styles
    └── app/
        ├── app.ts / app.html / app.css   Root component: top bar + <router-outlet>
        ├── app.routes.ts                 Browser routes
        ├── app.routes.server.ts          Server render mode (Client for all routes)
        ├── app.config.ts                 Router, HttpClient (fetch), hydration
        ├── app.config.server.ts          Adds server rendering on top of app.config
        │
        ├── pages/
        │   ├── dashboard/                Dashboard page
        │   └── vocabulary-form/          Add / Edit page
        │
        ├── components/
        │   ├── confirm-dialog/           <app-confirm-dialog>  (native <dialog>)
        │   └── toast-container/          <app-toast-container> (notifications)
        │
        └── services/
            ├── api.config.ts             API_BASE_URL  ← the API address
            ├── vocabulary.ts             VocabularyService (CRUD calls)
            ├── lookup.ts                 LookupService (topics, word types)
            ├── api-error.ts              apiErrorMessage(): HTTP error → readable text
            ├── toast.ts                  ToastService
            └── confirm.ts                ConfirmService
```

---

## 3. Services

### `api.config.ts`
```ts
export const API_BASE_URL = 'http://localhost:5048/api';
```
This is the **only place** where the API address is set. Every service builds its URLs from it.

> This URL is called **by the user's browser**, not by the frontend server. That's why `localhost:5048` works even when the frontend runs in Docker: the browser runs on your PC, and Docker publishes the API on your PC's port 5048.

### `VocabularyService`: words

| Method | HTTP call |
|---|---|
| `getAll({ topicId?, wordTypeId?, search? })` | `GET /api/Vocabulary?…` (empty filters are not sent) |
| `getById(id)` | `GET /api/Vocabulary/{id}` |
| `create(request)` | `POST /api/Vocabulary` |
| `update(id, request)` | `PUT /api/Vocabulary/{id}` |
| `delete(id)` | `DELETE /api/Vocabulary/{id}` |

### `LookupService`: dropdown data and stats

| Method | HTTP call |
|---|---|
| `getTopics()` | `GET /api/Topic` |
| `getWordTypes()` | `GET /api/WordType` |

Both are loaded together with `forkJoin`.

### `apiErrorMessage(error)`: user-friendly errors

| Situation | Message shown |
|---|---|
| Status `0` (API not running, CORS blocked, bad certificate) | "Cannot reach the API at … Is the backend running?" |
| Status `5xx` | "The server had a problem. Please try again." (the server's error details are never shown) |
| Plain-text body (for example a `409`) | The text from the API, e.g. "'apple' already exists with this word type." |
| Validation body (`400` with `errors`) | All validation messages joined together |
| `404` | "Not found. It may have been deleted." |

### `ToastService` and `ConfirmService`

- `toast.success(msg)` shows a message for 4 s; `toast.error(msg)` for 7 s. They're rendered by `<app-toast-container>`.
- `await confirm.ask({ title, message, confirmText })` returns `true` or `false`. It's rendered by `<app-confirm-dialog>` using the browser's native `<dialog>`; **Esc** or **Cancel** returns `false`.

Both components are placed once in `app.html`, so any page can use these services.

---

## 4. State management (signals)

Pages keep their state in Angular **signals**, not in a global store.

```ts
protected readonly words   = signal<Vocabulary[]>([]);
protected readonly search  = signal('');
protected readonly topicId = signal<number | null>(null);

protected readonly hasFilters = computed(() => this.search().trim() !== '' || ...);
```

The dashboard combines its filter signals into one `computed` value, turns it into an Observable (`toObservable`), and then:

```
filters change → debounceTime(250) → loading = true
              → switchMap(getAll(filter))   (cancels the previous request)
              → words = result, loading = false
              → on error: loadError = message, words = []
```

---

## 5. How the frontend talks to the API

```
┌──────────── Browser (your PC) ────────────┐
│ Angular app                               │
│  ├─ GET http://localhost:4000/      ──────┼──► Frontend server (Node/Express, port 4000)
│  │      (HTML, JS, CSS)                   │      returns the app files
│  │                                        │
│  └─ GET http://localhost:5048/api/... ────┼──► API (port 5048) ──► SQL Server
│         (JSON data)                       │
└───────────────────────────────────────────┘
```

Two things must be correct for this to work:
1. **`API_BASE_URL`** points to where the API is reachable **from the browser**.
2. **CORS** in the API's `Program.cs` allows the frontend's origin (`http://localhost:4200` and `http://localhost:4000`).

If either is wrong, the dashboard shows "Cannot reach the API…". Press **F12 → Console** to see the exact error.

---

## 6. SSR (server-side rendering) setup

The project was created with Angular SSR (`outputMode: "server"`), so the production build includes a **Node/Express server** (`src/server.ts`) that serves the app.

However, `app.routes.server.ts` sets **every route to `RenderMode.Client`**:
```ts
{ path: '**', renderMode: RenderMode.Client }
```
So the Node server only sends the app shell, and all data loading happens **in the browser**. This was chosen because the data comes from the API at runtime and there's nothing useful to pre-render.

### `allowedHosts` (important for Docker and deployment)

The SSR server only answers requests whose **Host header** is on an allowed list. This protects against SSRF attacks. It's set in `angular.json`:
```json
"security": { "allowedHosts": ["localhost"] }
```
If the list doesn't include your host, every page fails with:
```
Header "host" with value "localhost:4000" is not allowed.
```
When you deploy under a real domain, you can add it **without rebuilding** by setting an environment variable on the container:
```
NG_ALLOWED_HOSTS=localhost,myapp.example.com
```
(This variable replaces the list in `angular.json`.) `ng serve` doesn't enforce the list, so this error only appears in the built app.

---

## 7. Running locally (without Docker)

Requirements: **Node.js 22.22.3+, 24.15+ or 26+** (Angular 22's requirement; the Docker image uses Node 24) and npm.

```powershell
cd FrontEnd\English_FrontEnd
npm install          # first time, or after package.json changes
npm start            # = ng serve → http://localhost:4200
```
Start the API too, with the **http** profile (see `01-api.md`).

### npm scripts

| Command | What it does |
|---|---|
| `npm start` | Dev server with live reload at http://localhost:4200 |
| `npm run build` | Production build into `dist/English_FrontEnd/` (`browser/` + `server/`) |
| `npm run watch` | Development build that rebuilds on every change |
| `npm test` | Unit tests (Vitest) |
| `npm run serve:ssr:English_FrontEnd` | Runs the built SSR server at http://localhost:4000 (run `npm run build` first) |

### Build budgets

`angular.json` fails the production build if:
- the initial bundle is over **1 MB** (warning at 500 kB), or
- a single component's CSS is over **8 kB** (warning at 4 kB).

---

## 8. Adding a new page (example: Topics management)

1. **Service:** add methods to `LookupService`, or create `TopicService` in `services/`, using `API_BASE_URL`.
2. **Page:** create `pages/topics/topics.ts/.html/.css` (a standalone component), following the `Dashboard` pattern (signals, `apiErrorMessage`, toasts).
3. **Route:** add `{ path: 'topics', component: Topics, title: 'Topics · English Vocabulary' }` to `app.routes.ts`, **before** the `'**'` route.
4. **Nav link:** add `<a routerLink="/topics" routerLinkActive="active">Topics</a>` to `app.html`.
5. Run `npm start` and test, then rebuild the Docker image (see `03-docker.md`).
