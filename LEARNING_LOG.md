# Learning Log

Course: **Xoá mù chữ Cloud** · Team SBU3 · 19/10 – 1/12/2026 ([schedule](docs/Guides/guides.md))
Project: **English-Learning**. The course's sample app is *TeamBoard*; I apply each day's requirements to this project instead.

| Course (TeamBoard) | This project (English-Learning) |
|---|---|
| `Board` | `Topic` |
| `TaskItem` (belongs to a board) | `Vocabulary` (belongs to a topic and a word type) |
| `/api/boards`, `/api/boards/{id}/tasks`, `/api/tasks/{id}` | `/api/Topic`, `/api/Vocabulary?topicId={id}`, `/api/Vocabulary/{id}`, `/api/WordType` |
| EF Core + migrations | ADO.NET + SQL scripts (`database/`) |

Each entry: what I did, decisions and why, self-check against the day's criteria, what I learned, problems.

---

## T2 19/10 · Build the Web API (Dựng TeamBoard)

**Goal:** a Web API running locally with CRUD for the main entities.

### What I built
- ASP.NET Core Web API on .NET 10: `WFMTTC_API/Learning_EngLish`.
- Tables: `Topic`, `WordType`, `Vocabulary` (+ `Quiz`, `QuizQuestion` for later). One topic has many words; one word type has many words.
- Full CRUD (GET list, GET by id, POST, PUT, DELETE) for `Topic`, `WordType`, `Vocabulary`. `GET /api/Vocabulary` filters by `topicId`, `wordTypeId` and `search`.
- Layers: Controller (HTTP + status codes) → Repository (SQL) → `SqlConnectionFactory`.
- DTOs separate from table classes, validated with `[Required]` / `[StringLength]` (the day's stretch goal).
- Swagger UI at `/swagger`, only in Development.
- Angular frontend (`FrontEnd/English_FrontEnd`) that uses the API: dashboard, search, filters, add/edit/delete.
- Repo on GitHub: https://github.com/phucnthe172439/English-Learning

### Decisions
| Decision | Why |
|---|---|
| **ADO.NET instead of EF Core** (the course asks for EF Core + `InitialCreate`) | _TODO: my reason (e.g. to learn what SQL runs under the hood). The EF version is kept in `WFMTTC_API/_backup_before_adonet`._ |
| **Deleting a topic or word type that still has words is blocked** (409 Conflict), not cascaded | One click must not silently delete many words. The user moves or deletes the words first. Enforced by the foreign keys (no cascade). The API turns SQL error 547 into a clear 409 message |
| Deleting a quiz **does** delete its questions (`ON DELETE CASCADE`) | Questions have no meaning without their quiz |
| Status codes: 200 / 201 / 204 / 400 / 404 / 409 | 400 = invalid input or unknown `topicId`, 404 = id not found, 409 = duplicate or still in use |

### Self-check (Tự đánh giá)
Run with the API up (`docker compose up -d`, or F5 in Visual Studio).

| Criterion | How I checked | Result |
|---|---|---|
| `dotnet run` starts, `/swagger` shows all endpoints | Open http://localhost:5048/swagger | [ ] |
| Create 1 topic + 2 words; GET words of that topic returns exactly 2 | `POST /api/Topic`, 2× `POST /api/Vocabulary`, `GET /api/Vocabulary?topicId={id}` | [ ] |
| Unknown id → 404 | `GET /api/Vocabulary/999999` | [ ] |
| Create a word without `word` → 400 | `POST /api/Vocabulary` with `{"meaning":"x","wordTypeId":1,"topicId":1}` | [ ] |
| Deleting a topic that has words is handled consistently, reason documented | `DELETE /api/Topic/{id}` → 409 "This topic still has words…"; reason above and in the README | [ ] |
| Repo on GitHub, README explains how to run | [Frontend README](FrontEnd/English_FrontEnd/README.md), [docs/](docs/) | [ ] |

### What I learned
_In my own words:_
- _TODO_
- _TODO_

### Problems and fixes
| Problem | Fix |
|---|---|
| _TODO_ | _TODO_ |

### Next
T3 20/10: multi-stage Dockerfile for the API.

---

## T3 20/10 · Multi-stage Dockerfile

**Goal:** build an image of the API and run it in a container.

### What I built
- [`WFMTTC_API/Learning_EngLish/Dockerfile`](WFMTTC_API/Learning_EngLish/Dockerfile), 2 stages:
  1. `mcr.microsoft.com/dotnet/sdk:10.0`: `COPY Learning_EngLish.csproj` → `dotnet restore` → `COPY . .` → `dotnet publish -c Release`
  2. `mcr.microsoft.com/dotnet/aspnet:10.0`: copies only the published output, `EXPOSE 8080`, `USER $APP_UID`, `ENTRYPOINT dotnet Learning_EngLish.dll`
- [`.dockerignore`](WFMTTC_API/Learning_EngLish/.dockerignore) excludes `bin/`, `obj/`, `.git/`, `.vs/`, `.env`, `.env.*`, `secrets.json`, `launchSettings.json`, `*.md`. The frontend's `.dockerignore` excludes `.env` too.
- Frontend: same pattern ([`FrontEnd/English_FrontEnd/Dockerfile`](FrontEnd/English_FrontEnd/Dockerfile), `node:24-alpine` build → `node:24-alpine` runtime with `npm ci --omit=dev`).

### Image sizes (measured 21/10 with `docker image ls`)
| Image | Size | Note |
|---|---|---|
| `mcr.microsoft.com/dotnet/sdk:10.0` (build stage) | **1.3 GB** (1,304 MB) | Compiler + CLI, only used to build |
| `english-api` on `aspnet:10.0` (runtime, **used**) | **354 MB** | About **73% smaller** than the SDK image |
| `english-api` on `aspnet:10.0-noble-chiseled-extra` | 251 MB | Stretch goal, test only. No shell or package manager. `-extra` keeps ICU, which SqlClient needs |
| `english-api` on `aspnet:10.0-alpine` | 200 MB | Stretch goal, test only. musl libc, invariant globalization by default (may affect SqlClient and Vietnamese sorting) |

I kept the normal `aspnet:10.0` because chiseled has no shell, and T5 needs `docker exec -it <container> sh` for debugging. Chiseled or Alpine is a good choice later for production.

### Self-check (Tự đánh giá)
| Criterion | How I checked | Result |
|---|---|---|
| `docker build -t english-api .` succeeds | Build in `WFMTTC_API/Learning_EngLish` | ✅ |
| `docker run -p 8080:8080 english-api` starts the app (DB endpoints failing is expected) | Log shows `Now listening on: http://[::]:8080`; `GET /WeatherForecast` → 200, `GET /api/Topic` → 500 (no DB) | ✅ |
| Runtime image clearly smaller, MB written in the log | 1,304 MB → 354 MB (table above) | ✅ |
| Change a `.cs` file and rebuild: restore step shows `CACHED` | `docker build --progress=plain` after editing `TopicController.cs`: `COPY Learning_EngLish.csproj` **CACHED**, `RUN dotnet restore` **CACHED**; only `COPY . .` and `publish` re-ran | ✅ |
| Stretch: run as non-root | `USER $APP_UID`; `docker exec <container> id` → `uid=1654(app)` | ✅ |
| Stretch: try chiseled/alpine and compare sizes | 354 → 251 (chiseled-extra) → 200 MB (alpine) | ✅ |

Cache note: restore is skipped only while the `.csproj` is unchanged. When `dotnet user-secrets init` added `<UserSecretsId>` to the `.csproj`, the next build ran `dotnet restore` again (7.0 s). That's expected.

### In my own words
_TODO: explain each one in 1–2 sentences, without copying._
- **Image:**
- **Container:**
- **Layer:**
- **Registry:**

### Problems and fixes
| Problem | Fix |
|---|---|
| _TODO_ | _TODO_ |

### Next
T4 21/10: configuration from environment variables, `/health` endpoint, Docker Compose with SQL Server.

---

## T4 21/10 · Configuration, health check, Compose

**Goal:** run the API and SQL Server together with Docker Compose.

### What I built
- **Connection string from an environment variable:** `ConnectionStrings__DefaultConnection` (the course names it `ConnectionStrings__Default`; my app already used the key `DefaultConnection`). `__` = one level of JSON nesting, and environment variables override `appsettings.json`.
- **`GET /health`:** `AddHealthChecks()` with [`Data/DatabaseHealthCheck.cs`](WFMTTC_API/Learning_EngLish/Data/DatabaseHealthCheck.cs), which opens a connection (`Connect Timeout=3`) and runs `SELECT 1`. 200 `Healthy` / 503 `Unhealthy`.
- **[`docker-compose.yml`](docker-compose.yml):**
  - `db`: SQL Server **2025** with a named volume `sqldata` and a `healthcheck`. The course says 2022, but my PC runs SQL Server 2025 and a `.bak` only restores onto the same or a newer version.
  - `db-init`: one-shot container that creates the schema and seed data from `database/*.sql`.
  - `api` and `frontend`.
- **Secrets:** `SA_PASSWORD` and `APP_DB_PASSWORD` in `.env` (git-ignored); [`.env.example`](.env.example) is committed. The API uses its own `english_app` login (read and write only), not `sa`.
- Docs: [docs/04-database-docker.md](docs/04-database-docker.md).

### Self-check (Tự đánh giá)
| Criterion | How I checked | Result |
|---|---|---|
| `docker compose up -d` gives 2 running containers | `docker compose ps`: `db` Up (healthy), `api` Up, `frontend` Up, `db-init` Exited (0) | ✅ |
| `/health` Healthy when DB runs, Unhealthy after `docker compose stop db` | 200 Healthy (0.5 s) → stop db → 503 Unhealthy (7.9 s first call, then instant) → start db → 200 Healthy | ✅ |
| `docker compose down` then `up`: old data still there | Created topic `zz-persist-check` → `down` (volume kept) → `up` → topic still there (`db-init`: "already exists: skipping") → deleted it | ✅ |
| `.env` in `.gitignore`; repo has no real password | `git check-ignore .env` → ignored; `git log --all -- .env` → never committed; `git log -p` has no `Password=` values | ✅ |
| Stretch: `healthcheck` for the `db` service | `sqlcmd ... SELECT 1` every 10 s; `api` waits for `db-init`, which waits for `db` to be healthy | ✅ |

### Problems and fixes
| Problem | Fix |
|---|---|
| `/health` took 16 s to report Unhealthy | SqlClient doesn't cancel a pending `OpenAsync`, so the health check timeout didn't help. The health check now uses its own connection string with `Connect Timeout=3` |
| DBeaver: "Cannot open database WFMTTC2 requested by the login" | The DBeaver connection's **Database** field said `WFMTTC2`. Changed it to `EnglishVocabularyTraining` |
| Port 1433 already used by the SQL Server on my PC | The container's SQL Server is published on `14330` (`DB_PORT` in `.env`) |
| _TODO: others I hit_ | |

### What I learned
_In my own words:_
- _TODO: why environment variables instead of passwords in `appsettings.json`_
- _TODO: what a named volume does and what `down -v` would do_
- _TODO: difference between `depends_on` alone and `condition: service_healthy`_

### Going deeper
Labs: [docs/05-t4-deep-dive.md](docs/05-t4-deep-dive.md). Labs done and what I found:
- _TODO_

### Next
T5 22/10: migration on startup, wait for the database, seed data without duplicates, basic Linux/Docker commands.
