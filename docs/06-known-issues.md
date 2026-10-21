# 06 · Known issues and risks: health check and Docker Compose

Results of a review of `/health`, `database/init-db.sh` and `docker-compose.yml` (22/10/2026). Each item says what can go wrong, how it was checked, and its status.

| # | Issue | Severity | Status |
|---|---|---|---|
| [1](#1-half-built-database-was-never-repaired) | Half-built database was never repaired | High | ✅ Fixed |
| [2](#2-a--in-app_db_password-broke-the-login-script) | A `'` in `APP_DB_PASSWORD` broke the login script | Medium | ✅ Fixed |
| [3](#3-health-check-query-could-hang-for-30-s) | Health check query could hang for 30 s | Low | ✅ Fixed |
| [4](#4-changing-sa_password-after-the-first-run-blocks-the-whole-stack) | Changing `SA_PASSWORD` after the first run blocks the whole stack | Medium | ⚠️ Documented |
| [5](#5-ports-are-open-to-the-whole-network) | Ports are open to the whole network | Medium | ⚠️ Open |
| [6](#6-ways-to-lose-the-database) | Ways to lose the database | High (if it happens) | ⚠️ Back up |
| [7](#7-docker-stop-doesnt-shut-sql-server-down-cleanly) | `docker stop` doesn't shut SQL Server down cleanly | Low | ⚠️ Workaround |
| [8](#8-fixed-container-names-block-a-second-copy) | Fixed container names block a second copy | Low | ⚠️ Accepted |
| [9](#9-a--in-app_db_password-cuts-the-password-short) | A `;` in `APP_DB_PASSWORD` cuts the password short | Low | ⚠️ Documented |

Checked and **not** a problem:
- `docker compose down` on its own keeps the data (tested: marker row survived `down` + `up`).
- The API recovers by itself after a database restart, with no API restart needed (tested: `/health` 503 → 200).
- `/health` doesn't store anything: each call allocates memory that's freed afterwards, and `SELECT 1` writes nothing.
- Container logs can't fill the disk: this PC uses Docker's `local` log driver, which rotates at 5 × 20 MB.

---

## Fixed

### 1. Half-built database was never repaired

**What went wrong:** `init-db.sh` only checked whether the database *existed*. If `01-schema.sql` or `02-seed.sql` failed halfway (an error, or the container stopped during the first `up`), the database existed but was incomplete. Every later `docker compose up` skipped setup, and the API started against missing tables or empty lookup tables. It never repaired itself.

**Fix:**
- `01-schema.sql` and `02-seed.sql` each run in **one transaction** (`SET XACT_ABORT ON; BEGIN TRANSACTION; … COMMIT`). An error rolls everything back, so there's never a partial result.
- `init-db.sh` decides by looking at **tables and data**, not just the database:

| State | Action |
|---|---|
| 0 of 5 tables | Create the schema |
| 1–4 of 5 tables | **Exit 1** with a message, so the API doesn't start |
| 5 tables, `WordType` + `Topic` + `Vocabulary` all empty | Run the seed |
| 5 tables with data | Change nothing |

**Tested** in an isolated stack (`-p evt-init`, own container name, port and volume):

| Case | Result |
|---|---|
| Fresh volume | Schema + seed created, exit 0 |
| Second run | "Schema already exists" / "Data already exists", exit 0 |
| All rows deleted | Seed ran again: 8 word types, 7 words |
| One table dropped (4 of 5) | `ERROR: … has 4 of 5 tables (half-built database)`, **exit 1** |
| `SELECT 1/0` injected before `COMMIT` | "Divide by zero", **0 tables left**; next run built everything |

**If you hit the error:** restore a backup ([04 §6](04-database-docker.md#6-backup-and-restore)), recreate the missing table by hand, or start over with `docker compose down -v` (deletes all data).

### 2. A `'` in `APP_DB_PASSWORD` broke the login script

**What went wrong:** `03-app-login.sql` puts the password inside `N'…'`. A `'` in the password ended the string early, so `db-init` failed, and an unlucky password could even change the SQL.

**Fix:** `init-db.sh` doubles every `'` (`''`, SQL's escape) before passing the password to `sqlcmd`.

**Tested** with `APP_DB_PASSWORD=Ab1'cdEF!x9`: `english_app` logged in and read the topics.

### 3. Health check query could hang for 30 s

**What went wrong:** `Connect Timeout=3` only limits *connecting*. If SQL Server accepted the connection but was stuck, `SELECT 1` could wait up to SqlClient's default **30 s** command timeout, and so would every caller of `/health`.

**Fix:** `DatabaseHealthCheck` sets `CommandTimeout = 3` on the query.

**Measured behaviour now** (database stopped): first call 503 after ~8 s, next calls 503 immediately (SqlClient's pool blocking period), and 200 again once the database is back. Why the first call takes ~8 s rather than 3 s is open for investigation in [05 §B4](05-t4-deep-dive.md#b4-solve-your-own-mystery-79-s-then-0-s).

---

## Open: know about these

### 4. Changing `SA_PASSWORD` after the first run blocks the whole stack

**What goes wrong:** SQL Server reads `MSSQL_SA_PASSWORD` **only when the volume is first created**. If you change `SA_PASSWORD` in `.env` later, the `db` healthcheck logs in with the *new* password, SQL Server still has the *old* one, the healthcheck fails forever, `db` never becomes healthy, and **`db-init`, `api` and `frontend` never start**.

**Symptom:** `docker compose ps` shows `db` as `(unhealthy)` or `(health: starting)` for minutes; `docker compose logs db` shows `Login failed for user 'sa'`.

**Fix:** put the old password back in `.env`. To really change it, change it in SQL first, then in `.env`:

```sql
ALTER LOGIN sa WITH PASSWORD = '<new password>';
```

`APP_DB_PASSWORD` doesn't have this problem: `db-init` resets it on every `up`.

### 5. Ports are open to the whole network

**What goes wrong:** `ports: "14330:1433"` (and `5048`, `4000`) are published on **all network interfaces** (`netstat` shows `0.0.0.0:14330`). Other devices on the same Wi-Fi or LAN may reach SQL Server at `<your-PC-IP>:14330`, unless Windows Firewall blocks them. Only the `sa` password protects it.

**Fix (recommended):** bind to localhost only. DBeaver and the browser keep working on your PC:

```yaml
  db:
    ports:
      - "127.0.0.1:${DB_PORT:-14330}:1433"
```

Or remove `ports:` from `db` entirely if you don't need DBeaver: the API reaches `db:1433` inside the Docker network either way. See [05 §C2](05-t4-deep-dive.md#c2-ports-is-a-door-to-the-outside-and-its-open-wider-than-you-think).

### 6. Ways to lose the database

All data lives in the volume `english-learning_sqldata`. These **delete it**:

| Action | Deletes the data? |
|---|---|
| `docker compose down` | No |
| `docker compose down -v` | **Yes** |
| `docker volume rm english-learning_sqldata` | **Yes** |
| `docker volume prune -a` (or `prune` while the stack is down, on older Docker versions) | **Yes**: the volume counts as unused once `down` removed the containers |
| Docker Desktop → Troubleshoot → *Clean / Purge data* or *Reset to factory defaults* | **Yes** |
| Uninstalling Docker Desktop or WSL | **Yes** |

**Protection:** make a `.bak` regularly and keep it **outside** Docker ([04 §6.2](04-database-docker.md#62-back-up-the-container-database)):

```powershell
docker exec -it english-db /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C `
  -Q "BACKUP DATABASE EnglishVocabularyTraining TO DISK = N'/var/opt/mssql/backup/EnglishVocabularyTraining.bak' WITH COPY_ONLY, INIT"
docker cp english-db:/var/opt/mssql/backup/EnglishVocabularyTraining.bak .\EnglishVocabularyTraining.bak
```

(Keep `.bak` files out of Git.)

### 7. `docker stop` doesn't shut SQL Server down cleanly

**What happens:** measured on 22/10:

| How SQL Server was stopped | Exit code | Recovery work at the next start |
|---|---|---|
| `docker compose stop db` / `docker compose down` | **137** (killed) | Yes: "Recovery is writing a checkpoint" for `master` and `msdb` |
| T-SQL `SHUTDOWN` | 255 | None |

**Impact:** low. No committed data is lost, because SQL Server writes every change to its transaction log first and replays it at startup. Each start just does a little recovery work.

**Workaround** for a clean stop (for example before a backup, or before uninstalling Docker):

```powershell
docker compose exec db /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -Q "SHUTDOWN"
docker compose down
```

`sqlcmd` asks for the `sa` password.

### 8. Fixed container names block a second copy

**What goes wrong:** `container_name: english-db` (and `english-api`, `english-frontend`) is global on the machine. A second copy of the stack, such as a test run with `docker compose -p test up`, collides with the running one, or silently reuses its `english-db` container.

**Impact:** only when testing. If you need two copies, remove `container_name:` (Compose then names containers `<project>-db-1`), or override it in a second compose file:

```yaml
# test-override.yml
services:
  db:
    container_name: test-db
```

```powershell
docker compose -p test -f docker-compose.yml -f test-override.yml --env-file test.env up -d
```

### 9. A `;` in `APP_DB_PASSWORD` cuts the password short

**What goes wrong:** the API's connection string is built in `docker-compose.yml` as `...;Password=${APP_DB_PASSWORD};...`. In a connection string, `;` ends a value, so a password like `Ab1;cd!` becomes `Ab1` and the API gets `Login failed for user 'english_app'`.

**Fix:** don't use `;` (or `$`, `"`, `#`, spaces) in passwords. `!`, `_`, `-`, `@`, `.` and `'` are safe. The rule is in `.env.example`.
