# 01 · Backend API (`WFMTTC_API/Learning_EngLish`)

The API is an **ASP.NET Core Web API on .NET 10**. It stores English vocabulary in **SQL Server** and exposes it as a JSON REST API that the Angular frontend calls.

- **Main job:** create, read, update and delete (CRUD) **words**, **topics** and **word types**.
- **Data access:** plain **ADO.NET** (`Microsoft.Data.SqlClient`) with hand-written SQL. There's no Entity Framework.
- **Docs UI:** Swagger UI at `/swagger`, available only when `ASPNETCORE_ENVIRONMENT=Development`.

---

## 1. Folder structure

```
WFMTTC_API/
├── WFMTTC.slnx                     Visual Studio solution
└── Learning_EngLish/
    ├── Program.cs                  App startup: services, CORS, Swagger, routing
    ├── appsettings.json            Connection string + logging
    ├── appsettings.Development.json
    ├── Properties/launchSettings.json   Local run profiles (http / https / IIS Express)
    ├── Learning_EngLish.http       Ready-made test requests (VS / VS Code REST client)
    │
    ├── Controllers/                HTTP endpoints (one per resource)
    │   ├── VocabularyController.cs
    │   ├── TopicController.cs
    │   ├── WordTypeController.cs
    │   └── WeatherForecastController.cs   (template leftover, not used)
    │
    ├── Repositories/               All SQL lives here
    │   ├── VocabularyRepository.cs
    │   ├── TopicRepository.cs
    │   └── WordTypeRepository.cs
    │
    ├── DTOs/                       Request/response shapes sent over HTTP
    ├── Data/
    │   ├── SqlConnectionFactory.cs Opens SQL connections from the connection string
    │   ├── SqlErrors.cs            SQL Server error numbers the API reacts to
    │   └── DatabaseHealthCheck.cs  /health: is SQL Server reachable?
    ├── Models/                     Table classes (from earlier EF scaffolding, not used by the repositories)
    ├── Views/                      Razor views (leftover, not used: the app only maps API controllers)
    │
    ├── Dockerfile                  How to build the API image (see 03-docker.md)
    └── .dockerignore
```

---

## 2. How a request flows

```
Browser / Angular
      │  HTTP  GET /api/Vocabulary?topicId=1
      ▼
Controller           VocabularyController.GetAll(topicId, wordTypeId, search)
      │  calls
      ▼
Repository           VocabularyRepository.GetAllAsync(...)
      │  1. open connection   (SqlConnectionFactory)
      │  2. build SqlCommand  (SQL text + parameters)
      │  3. execute           (reader / scalar / non-query)
      ▼
SQL Server           EnglishVocabularyTraining database
      │  rows
      ▼
Repository maps rows → DTO (VocabularyResponse)
      ▼
Controller returns 200 OK + JSON
```

### Layer responsibilities

| Layer | Responsibility | Should NOT do |
|---|---|---|
| **Controller** | Read the HTTP input, call the repository, pick the HTTP status code (200 / 201 / 204 / 400 / 404 / 409) | Write SQL |
| **Repository** | Run SQL with parameters, map rows to DTOs | Know about HTTP |
| **SqlConnectionFactory** | Read `ConnectionStrings:DefaultConnection` and open connections | Hold connections open (connections are pooled and disposed after each use) |

### Dependency injection (registered in `Program.cs`)

| Service | Lifetime | Why |
|---|---|---|
| `SqlConnectionFactory` | Singleton | Only stores the connection string, so one instance is enough |
| `VocabularyRepository`, `TopicRepository`, `WordTypeRepository` | Scoped | A new instance per HTTP request |

---

## 3. Database

Database name: **`EnglishVocabularyTraining`** (SQL Server).

```
┌──────────────┐        ┌────────────────────┐        ┌──────────────┐
│ WordType     │ 1    * │ Vocabulary         │ *    1 │ Topic        │
│──────────────│────────│────────────────────│────────│──────────────│
│ WordTypeId PK│        │ VocabularyId PK    │        │ TopicId PK   │
│ Name (unique)│        │ Word               │        │ Name (unique)│
└──────────────┘        │ Meaning            │        └──────┬───────┘
                        │ WordTypeId FK      │               │ 1
                        │ TopicId FK         │               │
                        └─────────┬──────────┘               │ *
                                  │ 1                 ┌──────┴───────┐
                                  │                   │ Quiz         │
                                  │ *                 │──────────────│
                        ┌─────────┴──────────┐  *   1 │ QuizId PK    │
                        │ QuizQuestion       │────────│ Name         │
                        │────────────────────│        │ TopicId FK?  │
                        │ QuestionId PK      │        └──────────────┘
                        │ QuizId FK          │
                        │ VocabularyId FK    │
                        │ QuestionType       │
                        └────────────────────┘
```

| Table | Meaning | Used by the API? |
|---|---|---|
| `Vocabulary` | A word, its meaning, its word type and its topic | ✅ Yes |
| `Topic` | Groups words by subject (Travel, Food, …) | ✅ Yes |
| `WordType` | Part of speech (noun, verb, adjective, phrasal verb, …) | ✅ Yes |
| `Quiz`, `QuizQuestion` | Quizzes built from vocabulary | ❌ Not yet: the tables exist, but there are no endpoints |

**Rules enforced by the database** (the API turns violations into readable errors):
- `Topic.Name` and `WordType.Name` are unique.
- The same `Word` can't exist twice **with the same word type**.
- Foreign keys: you can't delete a topic or word type that still has words, or a word that's used in a quiz.

> The table-creation script isn't stored in this repo. Ask the team for it, or generate it from an existing database (DBeaver: right-click the database → **Generate SQL → DDL**).

---

## 4. Endpoints

Base URL:
- Local `http` profile or Docker: `http://localhost:5048/api`
- Local `https` profile: `https://localhost:7051/api`

### 4.1 Vocabulary: `/api/Vocabulary`

| Method | URL | Body | Success | Errors |
|---|---|---|---|---|
| GET | `/api/Vocabulary` | – | `200` list of words | – |
| GET | `/api/Vocabulary?topicId=1&wordTypeId=2&search=app` | – | `200` filtered list | – |
| GET | `/api/Vocabulary/{id}` | – | `200` one word | `404` not found |
| POST | `/api/Vocabulary` | `VocabularyRequest` | `201` created word + `Location` header | `400` invalid / unknown TopicId or WordTypeId · `409` duplicate |
| PUT | `/api/Vocabulary/{id}` | `VocabularyRequest` | `204` no content | `400` · `404` · `409` |
| DELETE | `/api/Vocabulary/{id}` | – | `204` no content | `404` · `409` used in a quiz |

**Filters** (all optional, and they can be combined):
- `topicId`: only words in this topic
- `wordTypeId`: only words of this type
- `search`: text found in **Word or Meaning** (`LIKE '%text%'`)

Results are sorted by `Word`.

**Request body (`VocabularyRequest`)**
```json
{
  "word": "apple",
  "meaning": "quả táo",
  "wordTypeId": 1,
  "topicId": 1
}
```
| Field | Rule |
|---|---|
| `word` | Required, max 100 characters |
| `meaning` | Required, max 500 characters |
| `wordTypeId` | ≥ 1, must exist |
| `topicId` | ≥ 1, must exist |

**Response (`VocabularyResponse`)**: includes the topic and word-type **names**, so the frontend doesn't need extra calls:
```json
{
  "vocabularyId": 12,
  "word": "apple",
  "meaning": "quả táo",
  "wordTypeId": 1,
  "wordTypeName": "noun",
  "topicId": 1,
  "topicName": "Food"
}
```

### 4.2 Topic: `/api/Topic`

| Method | URL | Body | Success | Errors |
|---|---|---|---|---|
| GET | `/api/Topic` | – | `200` list (sorted by name) | – |
| GET | `/api/Topic/{id}` | – | `200` | `404` |
| POST | `/api/Topic` | `{ "name": "Travel" }` | `201` | `400` · `409` name exists |
| PUT | `/api/Topic/{id}` | `{ "name": "Travel" }` | `204` | `404` · `409` |
| DELETE | `/api/Topic/{id}` | – | `204` | `404` · `409` still has words or quizzes |

`name`: required, max 100 characters.

Response:
```json
{ "topicId": 1, "name": "Food", "vocabularyCount": 25 }
```
`vocabularyCount` is calculated with `LEFT JOIN … GROUP BY`, so topics with 0 words are still listed.

### 4.3 WordType: `/api/WordType`

Same shape as Topic:

| Method | URL | Body | Success | Errors |
|---|---|---|---|---|
| GET | `/api/WordType` | – | `200` list | – |
| GET | `/api/WordType/{id}` | – | `200` | `404` |
| POST | `/api/WordType` | `{ "name": "phrasal verb" }` | `201` | `400` · `409` |
| PUT | `/api/WordType/{id}` | `{ "name": "..." }` | `204` | `404` · `409` |
| DELETE | `/api/WordType/{id}` | – | `204` | `404` · `409` still used by words |

`name`: required, max 50 characters.

```json
{ "wordTypeId": 1, "name": "noun", "vocabularyCount": 40 }
```

### 4.4 Health: `/health`

| Method | URL | Success | Failure |
|---|---|---|---|
| GET | `/health` | `200` body `Healthy` | `503` body `Unhealthy` |

Built with `AddHealthChecks()` and one check, `Data/DatabaseHealthCheck.cs`. It opens a connection with the app's connection string (with `Connect Timeout=3`) and runs `SELECT 1`. Use it to check that the API **and** its database work: from a browser, a load balancer, or later the App Runner health check (week 2). The response says only Healthy or Unhealthy. The error details go to the API log (`docker compose logs api`), not to the caller.

---

## 5. Error handling

Errors come back in two shapes. The frontend's `api-error.ts` handles both.

**1. Validation errors (400): automatic, from `[ApiController]` and the DTO attributes:**
```json
{
  "title": "One or more validation errors occurred.",
  "status": 400,
  "errors": { "Word": ["The Word field is required."] }
}
```

**2. Business errors (400 / 409): plain text written in the controllers:**
```
'apple' already exists with this word type.
```

Controllers catch the `SqlException`s listed in `Data/SqlErrors.cs`:

| SQL error number | Meaning | HTTP result |
|---|---|---|
| `547` | Foreign key violation | `400` on create/update (unknown id) · `409` on delete (row still in use) |
| `2627` | Unique constraint violation | `409 Conflict` |
| `2601` | Unique index violation | `409 Conflict` |

---

## 6. Security notes

- **SQL injection:** every value goes through `command.Parameters.Add(...)`. User input is never concatenated into SQL text. Keep it that way.
- **CORS:** only these browser origins may call the API (in `Program.cs`):
  - `http://localhost:4200` (`ng serve`, local dev)
  - `http://localhost:4000` (frontend Docker container)

  When the frontend gets a real domain (for example on AWS), add it here.
- **HTTPS redirection** is on (`UseHttpsRedirection`). Inside Docker there's only HTTP, so it logs `Failed to determine the https port for redirect`. That warning is harmless.
- **Secrets:** don't commit real passwords in `appsettings.json`. Override the connection string with an environment variable instead (see below).

---

## 7. Configuration

### Connection string

`appsettings.json`:
```json
"ConnectionStrings": {
  "DefaultConnection": "Server=localhost,1433;Database=EnglishVocabularyTraining;Trusted_Connection=True;TrustServerCertificate=True;"
}
```
`Trusted_Connection=True` means Windows login. That works when you run the API on Windows, but **not inside Docker** (Linux). In Docker, override it with an environment variable that uses a SQL login:

```
ConnectionStrings__DefaultConnection=Server=host.docker.internal,1433;Database=EnglishVocabularyTraining;User Id=<user>;Password=<password>;TrustServerCertificate=True;
```
A double underscore `__` in an environment variable name stands for one level of JSON nesting (`ConnectionStrings:DefaultConnection`). Environment variables override values from `appsettings.json`.

### Environment

| `ASPNETCORE_ENVIRONMENT` | Effect |
|---|---|
| `Development` | Swagger UI at `/swagger`, OpenAPI JSON at `/openapi/v1.json` |
| anything else (default `Production`) | No Swagger |

### Logs

The API writes logs to the **console** (stdout) only, not to files. Whoever runs the app collects them:

| How the API runs | Where to read the logs |
|---|---|
| Docker Compose | `docker compose logs api` (`-f` to follow, `--since 10m`, `--tail 50`) |
| Visual Studio | **Output** window (Show output from: *ASP.NET Core Web Server*) or the console window |
| `dotnet run` | The terminal |
| AWS App Runner (week 2–3) | CloudWatch Logs, collected automatically from stdout |

Docker keeps container logs inside Docker Desktop's VM. On this PC the log driver is `local`, which rotates automatically (5 files × 20 MB, compressed), so logs can't fill the disk. To keep a copy: `docker compose logs --no-color api > api.log`.

**What's logged:**

| What | Category | Level |
|---|---|---|
| Startup / shutdown | `Microsoft.Hosting.Lifetime` | Information |
| **One line per request**: method, path, status code, duration (ms). No headers, bodies or query strings | `Microsoft.AspNetCore.HttpLogging` | Information |
| `/health` failures (with the SQL error) | `Microsoft.Extensions.Diagnostics.HealthChecks` | Error |
| Other ASP.NET internals | `Microsoft.AspNetCore` | Warning and above only |

Request logging is configured in `Program.cs` (`AddHttpLogging` + `UseHttpLogging`). `/health` is excluded with `.WithHttpLogging(HttpLoggingFields.None)`, because platforms call it every few seconds.

Change levels without rebuilding, through environment variables, for example `Logging__LogLevel__Default=Debug` (see [05-t4-deep-dive.md A1](05-t4-deep-dive.md#a1-who-wins-change-a-setting-without-rebuilding)).

The warning `Failed to determine the https port for redirect` at startup is harmless in Docker: the container only serves HTTP on 8080, so `UseHttpsRedirection()` has nothing to redirect to.

---

## 8. Running the API locally (without Docker)

Requirements: **.NET 10 SDK** and a running SQL Server with the `EnglishVocabularyTraining` database.

```powershell
cd WFMTTC_API\Learning_EngLish
dotnet run --launch-profile http
```
- API: http://localhost:5048/api
- Swagger: http://localhost:5048/swagger

In Visual Studio, open `WFMTTC.slnx`, choose the **http** profile next to the ▶ button, and run.

> Use the **http** profile: the frontend is configured to call `http://localhost:5048/api`.

### Quick tests

- Open **Swagger**, pick an endpoint, then **Try it out → Execute**.
- Or open `Learning_EngLish.http` in Visual Studio or VS Code and click **Send Request**. Change `@host` at the top to `http://localhost:5048` first.
- Or use PowerShell:
  ```powershell
  Invoke-RestMethod http://localhost:5048/api/Topic
  ```

---

## 9. Adding a new feature (example: Quiz endpoints)

Follow the existing pattern:

1. **DTOs:** add `QuizResponse` and `QuizRequest` in `DTOs/` (with validation attributes).
2. **Repository:** add `QuizRepository` in `Repositories/` with parameterized SQL (copy `TopicRepository` as a starting point).
3. **Register it** in `Program.cs`: `builder.Services.AddScoped<QuizRepository>();`
4. **Controller:** add `QuizController` with `[ApiController]` and `[Route("api/[controller]")]`, and catch `SqlErrors` where needed.
5. Test in Swagger, then add matching calls to the frontend (see `02-frontend.md`).
6. Rebuild the Docker image (see `03-docker.md`).
