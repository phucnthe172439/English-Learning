# English-Learning

An English vocabulary app (word, Vietnamese meaning, word type, topic), used to learn and apply Docker and AWS in the **Xoá mù chữ Cloud** course (Team SBU3, 19/10 – 1/12/2026).

| Part | Tech | Folder |
|---|---|---|
| Frontend | Angular 22 + SSR (Node) | [`FrontEnd/English_FrontEnd`](FrontEnd/English_FrontEnd) |
| API | ASP.NET Core Web API, .NET 10, ADO.NET | [`WFMTTC_API/Learning_EngLish`](WFMTTC_API/Learning_EngLish) |
| Database | SQL Server 2025 | [`database`](database) (schema + seed scripts) |

```
Browser ──► frontend :4000          (Angular SSR)
Browser ──► api      :5048 → 8080   (REST API, /swagger, /health)
               api ──► db :1433      (SQL Server, data in volume "sqldata")
            db-init                  (creates the schema + seed data on first start, then exits)
```

---

## Quick start (Docker)

**Needs:** [Docker Desktop](https://www.docker.com/products/docker-desktop/) only. No .NET, Node or SQL Server install.

```powershell
git clone https://github.com/phucnthe172439/English-Learning.git
cd English-Learning
Copy-Item .env.example .env      # then open .env and set the two passwords
docker compose up -d --build
```

The first run downloads about 2 GB of images and takes a few minutes. Then open:

| URL | What |
|---|---|
| http://localhost:4000 | The app |
| http://localhost:5048/swagger | API docs (try `GET /api/Vocabulary`) |
| http://localhost:5048/health | `Healthy` when the API can reach the database |

Check that everything is up:

```powershell
docker compose ps -a     # db: healthy · db-init: Exited (0) · api, frontend: Up
```

Stop with `docker compose down`. **Your data is kept.** `docker compose down -v` deletes it.

### Environment variables (`.env`)

| Variable | Used for |
|---|---|
| `SA_PASSWORD` | SQL Server admin (`sa`) password inside the container |
| `APP_DB_PASSWORD` | Password of `english_app`, the login the API uses (read and write only) |
| `DB_PORT` | PC port for SQL Server, for DBeaver or SSMS (default `14330`) |

Passwords: at least 8 characters with upper case, lower case, a digit and a symbol. Don't use `$ " ; #` or spaces. `.env` is git-ignored; never commit it.

---

## Run for development (without Docker for the app)

| Part | Command | URL |
|---|---|---|
| Database only, in Docker | `docker compose up -d db db-init` | `localhost:14330` |
| API, in Visual Studio or a terminal | F5, or `dotnet run --launch-profile http` in `WFMTTC_API/Learning_EngLish` | http://localhost:5048/swagger |
| Frontend | `npm ci` then `npm start` in `FrontEnd/English_FrontEnd` | http://localhost:4200 |

To point the API at the Docker database, set its connection string as a **user secret**, not in `appsettings.json`. See [docs/04 §10.2](docs/04-database-docker.md#102-api-in-visual-studio--docker-database).

---

## Design notes

- **Deleting a topic or word type that still has words is blocked** (`409 Conflict`), not cascaded, so one click can't silently delete many words. Move or delete the words first. Deleting a quiz does delete its questions.
- **Status codes:** `400` invalid input, `404` id not found, `409` duplicate or still in use.
- **Data access is plain ADO.NET** with hand-written SQL in `Repositories/`. The schema lives in `database/01-schema.sql`, not in EF Core migrations.
- **No secrets in the repo or the images:** connection strings come from environment variables, and `.env` is excluded by both `.gitignore` and `.dockerignore`.

---

## Documentation

| Doc | Contents |
|---|---|
| [01 · API](docs/01-api.md) | Endpoints, request flow, error handling, configuration, logs |
| [02 · Frontend](docs/02-frontend.md) | Screens, components, services |
| [03 · Docker](docs/03-docker.md) | Dockerfiles explained, building images, pushing to Docker Hub or ECR |
| [04 · Database on Docker](docs/04-database-docker.md) | Compose, `.env`, backup and restore, connecting with DBeaver or Visual Studio |
| [05 · T4 deep dive](docs/05-t4-deep-dive.md) | Labs: configuration, health checks, Compose internals |
| [06 · Known issues](docs/06-known-issues.md) | Risks and their status (data loss, ports, passwords) |
| [Course schedule](docs/Guides/guides.md) | Weekly milestones and daily criteria |
| [LEARNING_LOG.md](LEARNING_LOG.md) | What I did and learned each day |

## Project structure

```
English-Learning/
├── docker-compose.yml        all 4 services
├── .env.example              copy to .env
├── database/                 01-schema.sql, 02-seed.sql, 03-app-login.sql, init-db.sh
├── WFMTTC_API/
│   └── Learning_EngLish/     API (Dockerfile inside)
├── FrontEnd/
│   └── English_FrontEnd/     Angular app (Dockerfile inside)
├── docs/                     guides 01–06, course schedule
└── LEARNING_LOG.md
```

## Troubleshooting

| Problem | Fix |
|---|---|
| `db` never becomes healthy | `docker compose logs db`. Usually `SA_PASSWORD` is too weak, or it was changed after the first run ([06 #4](docs/06-known-issues.md#4-changing-sa_password-after-the-first-run-blocks-the-whole-stack)) |
| `api` doesn't start | `docker compose logs db-init`. The database setup failed, and the error is shown there |
| Port already in use (5048, 4000, 14330) | Stop the other program (for example the API in Visual Studio), or change `DB_PORT` in `.env` |
| Dashboard says "Cannot reach the API" | Check http://localhost:5048/health. If it's not reachable, `docker compose up -d api` |

More: [docs/04 §8.3](docs/04-database-docker.md#83-troubleshooting).
