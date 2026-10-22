# 04 · Running the database on Docker

[03-docker.md](03-docker.md) runs the API and the frontend in Docker while SQL Server stays on your PC. This guide moves **SQL Server into a container too**, so the whole project starts with one command:

```powershell
docker compose up -d --build
```

Contents:

1. [What goes where (you don't "upload" a database)](#1-what-goes-where)
2. [The database files](#2-the-database-files)
3. [How the containers fit together](#3-how-the-containers-fit-together)
4. [The `.env` file](#4-the-env-file)
5. [First run, step by step](#5-first-run-step-by-step)
6. [Backup and restore](#6-backup-and-restore)
7. [The Dockerfiles explained (API first)](#7-the-dockerfiles-explained)
8. [Day-to-day commands and troubleshooting](#8-day-to-day-commands-and-troubleshooting) (known risks and their status: [06-known-issues.md](06-known-issues.md))
9. [`docker-compose.yml` explained](#9-docker-composeyml-explained)
10. [Connecting to the Docker database](#10-connecting-to-the-docker-database)

---

## 1. What goes where

The API and the frontend are **your code**, so you build images from them and push those images to a registry. A database is different: it's **Microsoft's program plus your data**.

| Thing | Where it lives | How others get it |
|---|---|---|
| SQL Server program | Microsoft's official image `mcr.microsoft.com/mssql/server:2025-latest` | Docker downloads it automatically. You never build or push it |
| Table structure and starter data | The SQL scripts in `database/` | Git |
| Your real data (words you added) | A Docker **volume** (`sqldata`) on your PC | A `.bak` backup file (section 6) |
| Passwords | `.env` on each PC | Never shared through Git or images |

Never put the data inside an image. Anyone who pulls an image can read it, and every rebuild would reset the data.

> **Why SQL Server 2025?** Your PC runs SQL Server 2025 (version 17, Express). SQL Server can restore a backup only on the **same or a newer** version, so the container has to be 2025 as well. Otherwise you couldn't move your PC data into it.

---

## 2. The database files

```
database/
├── 01-schema.sql      tables, constraints, indexes
├── 02-seed.sql        word types, topics, 7 sample words
├── 03-app-login.sql   the english_app login the API uses
└── init-db.sh         runs the scripts above inside Docker
```

### What changed compared to the original script (`docs/Schema/EnglishVocabularyTraining_Schema.sql`)

| Original | Now | Why |
|---|---|---|
| Tables created, then changed with `ALTER TABLE` (new columns, constraints, a dropped and re-created foreign key) | Each table is created **in its final form** | One clear definition per table. A fresh database is the same as your PC database: same columns in the same order, same constraint names |
| `CREATE DATABASE` always | `IF DB_ID(...) IS NULL CREATE DATABASE` | Doesn't fail if the database already exists |
| Sample words use fixed ids `(…, 1, 1)` | Looked up by name (`N'Noun'`, `N'Daily Life'`) | Doesn't break if identity values ever differ |
| Schema and data in one file | Split into schema / seed / login | You can re-run one part without the others |
| No login | `03-app-login.sql` creates `english_app` | The API needs a SQL login (Linux containers can't use Windows login) |

`english_app` gets **db_datareader + db_datawriter** (read and write rows) instead of `db_owner`. The API never changes tables, so it doesn't need more. If the API gets hacked, the attacker can't drop your tables.

### What `init-db.sh` does

It runs in a short-lived `db-init` container every time you run `docker compose up`:

```
How many of the 5 tables exist?
 ├── 0     → run 01-schema.sql (one transaction: all tables or none)
 ├── 1–4   → STOP with an error (half-built database: fix by hand or `down -v`)
 └── 5     → skip the schema
Are WordType, Topic and Vocabulary all empty?
 ├── yes   → run 02-seed.sql (one transaction: all rows or none)
 └── no    → skip, so your data is never touched
Then always → run 03-app-login.sql (create the login or fix it)
```

Because the schema and the seed each run in a single transaction, a failure in the middle leaves nothing behind, and the next `docker compose up` simply tries again. If `db-init` exits with an error, the API doesn't start (`service_completed_successfully`), so it never runs against a broken database.

So the scripts **only build an empty database once**. After that, your data lives in the volume and survives rebuilds, restarts and PC reboots.

> `.gitattributes` forces `init-db.sh` to keep Linux line endings (LF). With Windows line endings (CRLF), bash inside the container fails with errors like `$'\r': command not found`.

---

## 3. How the containers fit together

```
┌──────────────────────────── Your PC ─────────────────────────────┐
│  Browser ──► localhost:4000 (frontend)                           │
│  Browser ──► localhost:5048 (API)                                │
│  DBeaver ──► localhost:14330 (SQL Server in Docker)              │
│                                                                  │
│  ┌─── web-net ───────────────┐                                   │
│  │ frontend :4000            │                                   │
│  │            ┌──────────────┼──────────────────────────────┐    │
│  │            │ api :8080    │ ──── db:1433 ────► db  :1433 │    │
│  └────────────┼──────────────┘                    │ volume  │    │
│               │ db-init (runs once, then exits) ──┘ sqldata │    │
│               └─────────────────────────────────── db-net ──┘    │
│                                                                  │
│  SQL Server 2025 Express installed on the PC (unchanged, :1433)  │
└──────────────────────────────────────────────────────────────────┘
```

* Containers on the **same network** find each other **by service name**. That's why the API's connection string says `Server=db,1433`, not `host.docker.internal`.
* There are two networks: `db-net` (db, db-init, api) and `web-net` (api, frontend). The API is on both. The frontend is only on `web-net`, so it can't reach the database even if it's compromised.
* The container's SQL Server is published on PC port **14330**, because your PC's own SQL Server already uses 1433. Both can run at the same time.
* Start order is enforced: `db` must be **healthy** → `db-init` must **finish successfully** → `api` starts → `frontend` starts.

---

## 4. The `.env` file

Compose reads a file named **`.env`** in the same folder as `docker-compose.yml` and replaces every `${NAME}` in the compose file with its value.

```
.env.example   ← committed to Git: a template with fake values
.env           ← your real passwords, git-ignored, never committed
```

Create yours once:

```powershell
cd C:\Mini-Project\WFMTTC\English-Learning
Copy-Item .env.example .env
notepad .env
```

| Variable | Used by | Meaning |
|---|---|---|
| `SA_PASSWORD` | `db`, `db-init` | Password of `sa`, the SQL Server admin, inside the container |
| `APP_DB_PASSWORD` | `db-init`, `api` | Password of `english_app`. `db-init` sets it, and the API logs in with it |
| `DB_PORT` | `db` | PC port for DBeaver (default 14330) |

Rules:

* **Strong passwords:** at least 8 characters with upper case, lower case, a digit and a symbol. If `SA_PASSWORD` is too weak, SQL Server **refuses to start** and `docker compose logs db` shows why.
* **Avoid `$ " ;`, `#` and spaces.** Compose treats `$` as a variable and `#` can start a comment. `;` ends a value in the API's connection string, so the password would be cut off. `!`, `_`, `-`, `@`, `.` and `'` are safe.
* **Changing `APP_DB_PASSWORD` later:** edit `.env` and run `docker compose up -d`. `db-init` resets the login's password and the API gets the new connection string.
* **Changing `SA_PASSWORD` later doesn't work by editing `.env` alone.** SQL Server only reads it when the volume is **first created**. Either delete the volume (data is lost, see 8.2) or change it in SQL: `ALTER LOGIN sa WITH PASSWORD = '...'`, and then update `.env`.
* Check what Compose actually sees with `docker compose config`. It prints the final file with values filled in. Don't paste that output anywhere public, because it contains the passwords.

---

## 5. First run, step by step

Open **PowerShell** (not Git Bash: Git Bash rewrites paths like `/opt/...` and breaks `docker exec` commands).

### Step 1: Remove the old containers from 03-docker.md

They use the same names and ports (`english-api`, `english-frontend`):

```powershell
docker rm -f english-api english-frontend
```

### Step 2: Create `.env`

See section 4.

### Step 3: Start everything

```powershell
cd C:\Mini-Project\WFMTTC\English-Learning
docker compose up -d --build
```

The first run downloads the SQL Server image (about 1.5 GB) and builds the API and frontend images, so it takes a few minutes.

### Step 4: Check

```powershell
docker compose ps -a          # db: healthy, db-init: Exited (0), api and frontend: Up
docker compose logs db-init   # should end with "Database is ready."
```

* http://localhost:5048/health → `Healthy`. If you run `docker compose stop db`, it becomes `Unhealthy` (HTTP 503). Run `docker compose start db` and it's `Healthy` again.

* http://localhost:5048/swagger → `GET /api/Vocabulary` returns the 7 sample words
* http://localhost:4000 → the dashboard shows them

### Step 5 (optional): Connect DBeaver to the container

New connection → SQL Server → Host `localhost`, Port `14330`, Authentication **SQL Server Authentication**, User `sa`, Password = `SA_PASSWORD`, driver property `trustServerCertificate=true`.

At this point the container holds **starter data only**. To bring over the words already in your PC database, continue with section 6.1.

---

## 6. Backup and restore

A **backup** (`.bak`) is one file that contains a whole database: tables, data, users. **Restore** recreates the database from that file. It's how you move data between your PC, containers and (later) AWS RDS.

### 6.1 Move your PC data into the container

**a) Back up the PC database.** In DBeaver, connected to your **PC** SQL Server (`localhost`, port 1433):

```sql
BACKUP DATABASE EnglishVocabularyTraining
TO DISK = N'C:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\Backup\EnglishVocabularyTraining.bak'
WITH COPY_ONLY, INIT;
```

* The path is SQL Server's own Backup folder, where its service account is allowed to write. Another folder may give "Access is denied".
* `COPY_ONLY` = a one-off copy that doesn't disturb any regular backup schedule. `INIT` = overwrite the file if it exists.

**b) Copy the file into the container** (PowerShell):

```powershell
docker exec english-db mkdir -p /var/opt/mssql/backup
docker cp "C:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\Backup\EnglishVocabularyTraining.bak" english-db:/var/opt/mssql/backup/
```

`/var/opt/mssql/backup` is inside the volume, so the file survives restarts.

**c) Stop the API** (a restore needs the database to itself):

```powershell
docker compose stop api
```

**d) Restore.** In DBeaver, connected to the **container** (`localhost`, port **14330**, user `sa`):

```sql
-- 1. Look at the logical file names inside the backup
RESTORE FILELISTONLY
FROM DISK = N'/var/opt/mssql/backup/EnglishVocabularyTraining.bak';

-- 2. Restore over the starter database
RESTORE DATABASE EnglishVocabularyTraining
FROM DISK = N'/var/opt/mssql/backup/EnglishVocabularyTraining.bak'
WITH REPLACE,
     MOVE 'EnglishVocabularyTraining'     TO '/var/opt/mssql/data/EnglishVocabularyTraining.mdf',
     MOVE 'EnglishVocabularyTraining_log' TO '/var/opt/mssql/data/EnglishVocabularyTraining_log.ldf';
```

* `MOVE` is required: the backup remembers Windows paths (`C:\Program Files\...`), which don't exist in a Linux container. If step 1 shows different `LogicalName`s, use those in the `MOVE` lines.
* `REPLACE` = overwrite the existing database (the starter one).

**e) Re-link the API login, then start the API:**

```powershell
docker compose run --rm db-init
docker compose start api
```

Why step e is needed: the restored database contains the `english_app` **user** from your PC, linked to the PC's login by an internal ID (SID). The container's `english_app` **login** has a different SID, so the user is "orphaned" and the API gets `Login failed`. `03-app-login.sql` runs `ALTER USER english_app WITH LOGIN = english_app`, which fixes the link. (The user keeps the `db_owner` role it had on the PC. Remove it with `ALTER ROLE db_owner DROP MEMBER english_app;` if you want.)

Now refresh http://localhost:4000. You should see your own words.

### 6.2 Back up the container database

Do this before risky changes, or to share your data:

```powershell
docker exec -it english-db /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C `
  -Q "BACKUP DATABASE EnglishVocabularyTraining TO DISK = N'/var/opt/mssql/backup/EnglishVocabularyTraining.bak' WITH COPY_ONLY, INIT"
# sqlcmd asks for the sa password (it isn't saved in your PowerShell history)

docker cp english-db:/var/opt/mssql/backup/EnglishVocabularyTraining.bak .\EnglishVocabularyTraining.bak
```

You can also run the same `BACKUP` statement in DBeaver while connected to port 14330.

> Keep `.bak` files **out of Git**. They contain all your data and grow over time. Store them in a cloud drive or S3 instead.

### 6.3 Restore a `.bak` somewhere else

| Target | How |
|---|---|
| Another PC's container | Same as 6.1, from step b |
| Back onto your PC's SQL Server | Copy the file into the PC's `...\MSSQL\Backup\` folder → `RESTORE DATABASE ... WITH REPLACE, MOVE '...' TO 'C:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\DATA\....mdf', ...` |
| AWS RDS for SQL Server (later) | RDS restores native `.bak` files from S3 through `msdb.dbo.rds_restore_database`. The RDS engine version must be 2025 or newer, for the same reason as section 1 |

### 6.4 Backup vs scripts: which one when?

| You want to… | Use |
|---|---|
| Create an **empty** database with the right structure (new teammate, CI, test) | The scripts (automatic on first `docker compose up`) |
| Move or keep **real data** | Backup / restore |
| Change the table structure | Edit `01-schema.sql` **and** apply the same change to existing databases with an `ALTER TABLE` script. The init scripts don't re-run on a database that already exists |

---

## 7. The Dockerfiles explained

### 7.1 API: `WFMTTC_API/Learning_EngLish/Dockerfile`

```dockerfile
# ---------- Stage 1: build ----------
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY Learning_EngLish.csproj .
RUN dotnet restore

COPY . .
RUN dotnet publish -c Release -o /app --no-restore

# ---------- Stage 2: run ----------
FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app .

EXPOSE 8080
USER $APP_UID
ENTRYPOINT ["dotnet", "Learning_EngLish.dll"]
```

Line by line:

| Line | What it does | Why it's written this way |
|---|---|---|
| `FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build` | Starts from Microsoft's image that has the **.NET 10 SDK** (compiler + `dotnet` CLI), and names this stage `build` | You need the SDK to compile, but not to run. `AS build` lets stage 2 copy files out of it |
| `WORKDIR /src` | Creates `/src` and makes it the current folder for the next lines | Like `cd`, but it also creates the folder |
| `COPY Learning_EngLish.csproj .` | Copies **only** the project file into `/src` | Docker caches every step. If the `.csproj` didn't change, the next step comes from cache |
| `RUN dotnet restore` | Downloads the NuGet packages listed in the `.csproj` (`Microsoft.Data.SqlClient`, OpenAPI, Swagger UI) | Slow step, so it's done before copying the code. Editing a `.cs` file doesn't re-download packages |
| `COPY . .` | Copies the rest of the source folder into `/src` | `.dockerignore` filters it first: `bin/`, `obj/`, `.vs/`, `*.http`, `launchSettings.json` and so on are left out, so stale local builds can't sneak in |
| `RUN dotnet publish -c Release -o /app --no-restore` | Compiles an optimized **Release** build and puts the ready-to-run files (`Learning_EngLish.dll`, dependencies, `appsettings.json`) into `/app` | `--no-restore` = packages are already there from the cached step |
| `FROM mcr.microsoft.com/dotnet/aspnet:10.0` | **Starts over** from a much smaller image that has only the ASP.NET runtime | Everything from stage 1 (SDK, source code, `obj/`) is thrown away. Only what you copy next is kept. That means a smaller image and no compiler or source code for an attacker to use |
| `WORKDIR /app` | Run folder | |
| `COPY --from=build /app .` | Takes **only** the published output from stage 1 | This is the "multi-stage" trick |
| `EXPOSE 8080` | Documents that the app listens on 8080 | Doesn't open anything by itself. The port mapping (`5048:8080` in compose) does. .NET 8+ containers listen on 8080 by default |
| `USER $APP_UID` | Switches to the image's built-in non-root user `app` (uid 1654) | Without it the app runs as **root**. If the API is ever compromised, the attacker gets fewer rights. Works because the app listens on 8080 (non-root users can't use ports below 1024) and doesn't write files. Check with `docker exec english-api id` |
| `ENTRYPOINT ["dotnet", "Learning_EngLish.dll"]` | The command that runs when the container starts | The JSON-array form runs `dotnet` directly (no shell), so `docker stop` signals reach the app and it shuts down cleanly |

What's **not** in the image, on purpose:

* **The connection string with a password.** `appsettings.json` inside the image still has the PC's Windows-login connection string. At run time, the environment variable `ConnectionStrings__DefaultConnection` (from compose) **overrides** it, since ASP.NET reads environment variables after JSON files and `__` means one level of nesting. The same image works on your PC, a teammate's PC and AWS; only the variables change.
* **The database.** The API is stateless, so you can delete and recreate it at any time.

### 7.2 Frontend: `FrontEnd/English_FrontEnd/Dockerfile`

Same two-stage idea, with Node instead of .NET (see [03-docker.md §4.2](03-docker.md#42-frontend-dockerfile-explained)):

| Stage | .NET API | Angular frontend |
|---|---|---|
| Build image | `dotnet/sdk:10.0` | `node:24-alpine` |
| Cached dependency step | `COPY *.csproj` → `dotnet restore` | `COPY package*.json` → `npm ci` |
| Build step | `dotnet publish` | `npm run build` (`ng build`) |
| Run image | `dotnet/aspnet:10.0` (runtime only) | `node:24-alpine` + `npm ci --omit=dev` (runtime packages only) |
| Start command | `dotnet Learning_EngLish.dll` | `node dist/English_FrontEnd/server/server.mjs` (SSR server) |

Note that `API_BASE_URL` is compiled **into** the frontend bundle at build time, because it runs in the user's browser. So changing the API address means rebuilding the frontend image, unlike the API's connection string.

### 7.3 Why the database has no Dockerfile

You don't need to change Microsoft's SQL Server program, only configure it. Configuration comes from environment variables (`ACCEPT_EULA`, `MSSQL_PID`, `MSSQL_SA_PASSWORD`) and the structure comes from the scripts that `db-init` runs. Building your own SQL Server image would mean rebuilding it for every security update Microsoft publishes. With the official image, `docker compose pull` is enough.

---

## 8. Day-to-day commands and troubleshooting

### 8.1 Commands

Run all of these from `C:\Mini-Project\WFMTTC\English-Learning`.

| Command | What it does |
|---|---|
| `docker compose up -d --build` | Build what changed and start everything |
| `docker compose up -d --build api` | Rebuild and restart only the API (the same works for `frontend`) |
| `docker compose ps -a` | Status of all services, including `db-init` |
| `docker compose logs -f api` | Follow the API's output (`db`, `db-init`, `frontend` work the same way) |
| `docker compose stop` / `docker compose start` | Stop or start everything; containers and data are kept |
| `docker compose down` | Remove the containers; **the data stays** in the volume |
| `docker compose run --rm db-init` | Re-run the init script (for example after a restore) |
| `docker compose pull db` | Get the latest SQL Server 2025 updates (then `up -d`) |

### 8.2 Starting over with a fresh database

```powershell
docker compose down -v      # -v also deletes the sqldata volume: ALL DATA IS LOST
docker compose up -d --build
```

Back up first (6.2) if there's anything you want to keep.

### 8.3 Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `db` keeps restarting / is never healthy | `SA_PASSWORD` too weak, or `.env` missing | `docker compose logs db`. Fix `.env`. If the volume was already created with another password, see the `SA_PASSWORD` note in section 4 |
| `db-init` exited with code 1 | SQL error in a script, a weak `APP_DB_PASSWORD`, or "half-built database" (some tables missing) | `docker compose logs db-init` shows the exact error. For a half-built database: restore a backup, recreate the missing table by hand, or `docker compose down -v` (deletes all data) |
| `db` never becomes healthy after you changed `SA_PASSWORD` in `.env` | The volume still has the **old** `sa` password, so the healthcheck logs in with the new one and fails | Put the old password back in `.env`, or change it in SQL first (`ALTER LOGIN sa WITH PASSWORD = '...'`) and then in `.env` |
| `$'\r': command not found` in `db-init` logs | `init-db.sh` was saved with Windows line endings | In VS Code, click `CRLF` in the status bar → `LF`, save, and run `docker compose up -d` again |
| API: `Login failed for user 'english_app'` after a restore | Orphaned user (6.1 e) | `docker compose run --rm db-init` |
| `Bind for 0.0.0.0:14330 failed: port is already allocated` | Something else uses the port | Change `DB_PORT` in `.env` |
| `Conflict. The container name "/english-api" is already in use` | An old container from 03-docker.md still exists | `docker rm -f english-api english-frontend` |
| `RESTORE`: "The database was backed up on a server running version 17…" / "not supported" | Backup from a newer SQL Server than the container | Keep the image at `2025-latest` (or newer) |
| `RESTORE`: "Operating system error 5 (Access is denied)" | The copied file isn't readable by SQL Server's user | `docker exec -u 0 english-db chown mssql /var/opt/mssql/backup/EnglishVocabularyTraining.bak` |
| `RESTORE`: "exclusive access could not be obtained" | The API (or DBeaver) is using the database | `docker compose stop api`, and in DBeaver connect to `master` instead of the database |
| `docker exec ... /opt/mssql-tools18/...: no such file` mentioning `C:/Program Files/Git` | The command ran in Git Bash, which rewrites Linux paths | Use PowerShell, or prefix the command with `MSYS_NO_PATHCONV=1` |

---

## 9. `docker-compose.yml` explained

The file is in the repo root: `C:\Mini-Project\WFMTTC\English-Learning\docker-compose.yml`. It doesn't merge anything. You still get **separate containers**, but their `docker run` settings are written down once, together with the start order.

| `docker run` flag | Compose key |
|---|---|
| `--name english-api` | `container_name: english-api` |
| `-p 5048:8080` | `ports: ["5048:8080"]` |
| `-e KEY=value` | `environment: { KEY: value }` |
| `-v sqldata:/var/opt/mssql` | `volumes: [sqldata:/var/opt/mssql]` |
| `docker build -t english-api ./folder` | `build: ./folder` + `image: english-api` |
| `docker network create` + `--network` | `networks:` at the top level + `networks:` per service (without it, Compose puts every service on one `default` network) |

What `docker compose up` does:

1. Reads `.env` and fills in every `${...}`.
2. Creates the networks `english-learning_db-net` and `english-learning_web-net`, and the volume `english-learning_sqldata` (prefix = `name:` at the top of the file).
3. Pulls the SQL Server image. Builds the API and frontend images if they don't exist yet (`--build` forces a rebuild).
4. Starts the services in order:

```
db  ──healthy──►  db-init  ──exited with 0──►  api  ──started──►  frontend
```

### 9.1 `db`

| Key | Meaning |
|---|---|
| `image: mcr.microsoft.com/mssql/server:2025-latest` | Microsoft's ready-made SQL Server 2025. Nothing is built |
| `container_name: english-db` | Fixed name for `docker exec english-db ...` (otherwise it would be `english-learning-db-1`) |
| `ACCEPT_EULA: "Y"` | Accepts Microsoft's licence. SQL Server won't start without it |
| `MSSQL_PID: Developer` | Free, full-featured edition, allowed for development only |
| `MSSQL_SA_PASSWORD: ${SA_PASSWORD}` | Admin password from `.env`. Only read when the volume is first created |
| `ports: "${DB_PORT:-14330}:1433"` | PC port 14330 → container port 1433. `:-14330` = default if `DB_PORT` isn't set |
| `volumes: sqldata:/var/opt/mssql` | **The data line.** SQL Server's files live in a volume outside the container, so deleting the container doesn't delete the data |
| `healthcheck` | Every 10 s, runs `SELECT 1` inside the container. Success marks the container **healthy**. Failures in the first 30 s (`start_period`) don't count. `$$` produces a literal `$`, so the variable is read inside the container |

### 9.2 `db-init`

| Key | Meaning |
|---|---|
| `image:` (same as `db`) | Used only for its `sqlcmd` tool. It doesn't run a second SQL Server |
| `depends_on: db: condition: service_healthy` | Waits until SQL Server actually answers, not just until the container starts |
| `volumes: ./database:/scripts:ro` | **Bind mount**: your PC folder `database/` appears as `/scripts`, read-only. Script edits are seen immediately, with no rebuild |
| `entrypoint: ["/bin/bash", "/scripts/init-db.sh"]` | Replaces "start SQL Server" with "run my script" |
| `restart: "no"` | It's meant to exit when done, so Docker doesn't restart it |

### 9.3 `api`

| Key | Meaning |
|---|---|
| `build: ./WFMTTC_API/Learning_EngLish` | Builds from that folder's Dockerfile (section 7.1) |
| `image: english-api` | Name of the built image |
| `ConnectionStrings__DefaultConnection: "Server=db,1433;..."` | Overrides `appsettings.json`. **`db` = the service name.** On a Compose network, services reach each other by name. The port is **1433**, because this traffic stays inside the Docker network. 14330 exists only for your PC |
| `depends_on: db-init: condition: service_completed_successfully` | Starts only if the init script exited with code 0, so it never runs against a half-built database |

### 9.4 `frontend`

`depends_on: [api]` only waits for the API container to **start**. That's enough: the browser calls the API directly, not the frontend container.

### 9.5 `volumes: sqldata:`

Declares the named volume. Compose creates it once and **only deletes it with `docker compose down -v`**.

### 9.6 What else you can do

| Goal | How |
|---|---|
| Rebuild only one service | `docker compose up -d --build api` |
| Start only the database (API runs in Visual Studio, see 10.2) | `docker compose up -d db db-init` |
| Shell inside a container | `docker compose exec api bash` (`sh` for the frontend) |
| Show the final file with values filled in (contains passwords!) | `docker compose config` |
| Restart automatically when Docker Desktop starts | Add `restart: unless-stopped` to `db`, `api`, `frontend` |
| Personal settings that aren't committed | `docker-compose.override.yml` (git-ignored, merged in automatically) |
| Rebuild or sync on file save | `docker compose watch` with a `develop.watch` section |
| Services that start only when asked (for example a DB admin UI) | `profiles: [tools]` → `docker compose --profile tools up` |

---

## 10. Connecting to the Docker database

The connection details depend on **where the program that connects is running**:

| Who connects | Runs where | Server | Port | Login |
|---|---|---|---|---|
| API started by `docker compose` | Docker network | `db` | `1433` | `english_app` |
| API started from Visual Studio / `dotnet run` | Your PC | `localhost` | `14330` | `english_app` |
| DBeaver / SSMS | Your PC | `localhost` | `14330` | `sa` (admin) or `english_app` |
| API in a container started with plain `docker run` (03-docker.md) | Docker, but **not** on the Compose network | `host.docker.internal` | `14330` | `english_app` |

Your PC's own SQL Server is still at `localhost:1433`, so the **port number decides which server you reach**: 1433 = PC, 14330 = Docker.

### 10.1 API in Docker: nothing to do

The connection string is already in `docker-compose.yml`, and the password comes from `.env`. Check it with:

```powershell
docker compose logs api        # no SqlException at startup
```

and `GET /api/Topic` in http://localhost:5048/swagger.

### 10.2 API in Visual Studio → Docker database

Useful for daily coding: debugging and hot reload in Visual Studio, with the database in Docker.

**a) Start only the database** (stop the API container if it's running, because it uses port 5048):

```powershell
cd C:\Mini-Project\WFMTTC\English-Learning
docker compose stop api frontend
docker compose up -d db db-init
```

**b) Store the connection string as a user secret.** Don't put it in `appsettings.Development.json`: that file is committed to Git, and the password would be committed with it. User secrets are kept outside the repo, in `%APPDATA%\Microsoft\UserSecrets\`, and ASP.NET reads them automatically when `ASPNETCORE_ENVIRONMENT=Development` (which `launchSettings.json` already sets).

```powershell
cd C:\Mini-Project\WFMTTC\English-Learning\WFMTTC_API\Learning_EngLish
dotnet user-secrets init        # once: adds a <UserSecretsId> to the .csproj
dotnet user-secrets set "ConnectionStrings:DefaultConnection" "Server=localhost,14330;Database=EnglishVocabularyTraining;User Id=english_app;Password=<APP_DB_PASSWORD from .env>;TrustServerCertificate=True;"
dotnet user-secrets list        # check
```

In Visual Studio you can do the same with right-click on the project → **Manage User Secrets**, which opens `secrets.json`:

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Server=localhost,14330;Database=EnglishVocabularyTraining;User Id=english_app;Password=<APP_DB_PASSWORD from .env>;TrustServerCertificate=True;"
  }
}
```

**c) Run the API** (F5 or `dotnet run`). It now uses the Docker database.

**d) Switch back to the PC database:** remove the secret, and `appsettings.json` (`localhost,1433`, Windows login) applies again:

```powershell
dotnet user-secrets remove "ConnectionStrings:DefaultConnection"
```

Where the connection string comes from, highest priority first:

```
1. Environment variable ConnectionStrings__DefaultConnection   ← docker-compose.yml
2. User secrets (Development only)                              ← 10.2
3. appsettings.Development.json
4. appsettings.json                                             ← PC database (default)
```

The API in Docker never sees your user secrets (they're on your PC, not in the image), so the two setups don't interfere.

### 10.3 DBeaver → Docker database

New Database Connection → **SQL Server**:

| Field | Value |
|---|---|
| Host | `localhost` |
| Port | `14330` |
| Database | `EnglishVocabularyTraining` (or `master` for restores) |
| Authentication | SQL Server Authentication |
| Username / Password | `sa` / `SA_PASSWORD`, or `english_app` / `APP_DB_PASSWORD` (read and write only) |
| Driver properties tab | `trustServerCertificate` = `true` (the container uses a self-signed certificate) |

Name the connection something like **"English DB (Docker)"** so you don't mix it up with the PC one.

### 10.4 Connection problems

| Error | Cause | Fix |
|---|---|---|
| `A network-related or instance-specific error` | Database container not running, or wrong port | `docker compose ps`. `db` must be `healthy`. Use port **14330** from the PC |
| `Login failed for user 'english_app'` | Wrong password, or orphaned user after a restore | Password must equal `APP_DB_PASSWORD` in `.env`. After a restore: `docker compose run --rm db-init` |
| `The certificate chain was issued by an authority that is not trusted` | Missing `TrustServerCertificate=True` | Add it to the connection string (or the DBeaver driver property) |
| The API in Visual Studio still shows the PC's words | The user secret isn't set, or the app isn't in Development | `dotnet user-secrets list`. Run with the `http`/`https` profile, which sets `ASPNETCORE_ENVIRONMENT=Development` |
| `docker compose up` fails: port 5048 in use | The API is also running in Visual Studio | Stop one of them. Both can't use 5048 |
