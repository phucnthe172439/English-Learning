# 05 · T4 deep dive: configuration, health checks, Compose

T4 21/10's criteria are met (see `LEARNING_LOG.md`). This guide goes **further**, with hands-on labs you run on **your own stack**. Every lab has: what to do → what you'll see → why it matters for the next weeks (AWS, CI/CD).

Do them in any order. Pick 2–3, and write what you learned in the log under T4.

| Part | Topic | Time |
|---|---|---|
| [A](#a-configuration) | Configuration: who wins, why env vars aren't secret, fail fast | 45 min |
| [B](#b-health-checks) | Health checks: liveness vs readiness, Degraded, your 7.9 s mystery | 60 min |
| [C](#c-compose-under-the-hood) | Compose under the hood: DNS, ports, volumes, restarts, memory | 60 min |
| [D](#d-scan-your-images) | Scan your images for vulnerabilities | 15 min |
| [E](#e-read-12-factor-app) | Read: 12-Factor App, mapped to this project | 30 min |
| [F](#f-check-yourself) | Questions to check yourself | – |

Run everything in **PowerShell** from `C:\Mini-Project\WFMTTC\English-Learning`, with the stack up (`docker compose up -d`).

---

## A. Configuration

### A1. Who wins? Change a setting without rebuilding

ASP.NET Core reads configuration from several places. **Later sources override earlier ones:**

```
1. appsettings.json                    lowest
2. appsettings.{Environment}.json
3. User secrets                        (only in Development)
4. Environment variables               ← docker-compose.yml "environment:"
5. Command-line arguments              highest
```

**Lab:** turn on Debug logging **without touching code or rebuilding the image**:

```powershell
docker compose stop api
docker compose run --rm -e Logging__LogLevel__Default=Debug api
# Ctrl+C to stop, then: docker compose start api
```

**You'll see** many `dbug:` lines that normally aren't there. The same image behaves differently because of one variable.

**Why `__` and not `:`?** The JSON key is `Logging:LogLevel:Default`, but `:` isn't allowed in environment variable names on Linux shells. .NET translates `__` into `:`.

**Why it matters:** in week 2, App Runner runs **the exact image you built here**. Only its environment variables differ. Same image in dev, staging and production is the point of week 1 ("build once, configure per environment").

### A2. Environment variables are NOT secret

**Lab:** run these and look for the password (don't screenshot it):

```powershell
docker inspect english-api --format '{{range .Config.Env}}{{println .}}{{end}}'
docker compose config                      # the whole file, values filled in
docker compose exec api sh -c 'tr "\0" "\n" < /proc/1/environ'   # from inside the container
```

**You'll see** `ConnectionStrings__DefaultConnection=...Password=...` in plain text, three different ways.

**Why:** anyone who can run `docker` on a machine can read every container's environment. Environment variables also show up in crash dumps, `/proc`, and sometimes in logs when an app prints its config. They're **better than a password in Git**, but they're not a vault.

**Where real secrets go:**

| Where | How the app gets it | When |
|---|---|---|
| Environment variable | `ConnectionStrings__...` | Local dev (now), week 2 temporarily |
| **File** mounted at `/run/secrets/<name>` | Compose `secrets:`; ASP.NET `AddKeyPerFile("/run/secrets")` | Docker / Compose, Kubernetes |
| **AWS Secrets Manager**, fetched with an IAM role | App Runner references the secret; no password in any config | **Week 3** (`teamboard/staging/db`) |

**Challenge (optional):** move the API's connection string from `environment:` to a Compose secret.

```yaml
# docker-compose.yml
services:
  api:
    secrets:
      - source: api_db_connection
        target: ConnectionStrings__DefaultConnection   # becomes /run/secrets/ConnectionStrings__DefaultConnection
    # ...and remove ConnectionStrings__DefaultConnection from environment:

secrets:
  api_db_connection:
    environment: API_DB_CONNECTION                     # full connection string, defined in .env
```

```csharp
// Program.cs, right after CreateBuilder: each file name = key, each file content = value ("__" = ":")
builder.Configuration.AddKeyPerFile("/run/secrets", optional: true);
```

Check:
- `docker compose exec api ls -l /run/secrets` shows the file, and it's readable by the `app` user.
- `docker inspect english-api` **no longer** shows the password.
- `/health` is still Healthy.

### A3. Secrets in images live forever

**Lab:**

```powershell
docker history english-api --no-trunc --format '{{.CreatedBy}}' | Select-String 'ENV|ARG|USER'
```

**You'll see** every `ENV` and `ARG` baked into each layer (`APP_UID=1654`, `ASPNETCORE_HTTP_PORTS=8080`, …). If a Dockerfile ever had `ENV DB_PASSWORD=...` or `ARG PASSWORD`, **anyone who pulls the image can read it**, even if a later line removes it. Layers are append-only.

Rules:
- Never put secrets in `ENV` or `ARG` in a Dockerfile.
- A secret needed **during the build** (for example a private NuGet feed) goes in `RUN --mount=type=secret,id=...` (BuildKit), which isn't stored in a layer.
- That's also why `.dockerignore` excludes `.env` (T3): `COPY . .` would otherwise bake it into a layer.

### A4. Fail fast: start broken, or don't start?

**Think first, then test:** what happens with a **wrong** database password?

```powershell
docker compose stop api
docker compose run --rm -p 5049:8080 -e "ConnectionStrings__DefaultConnection=Server=db,1433;Database=EnglishVocabularyTraining;User Id=english_app;Password=wrong;TrustServerCertificate=True;" api
# other window:
Invoke-WebRequest http://localhost:5049/health -SkipHttpErrorCheck | Select StatusCode, Content
Invoke-WebRequest http://localhost:5049/api/Topic -SkipHttpErrorCheck | Select StatusCode
```

**You'll see** the app **start normally** ("Application started"), then every request fail. Nothing told you at startup.

Two schools:

| Approach | Behaviour | Trade-off |
|---|---|---|
| **Start anyway** (current) | Container runs, `/health` says Unhealthy | Survives a DB that's briefly down at startup. But a typo stays invisible until the first request |
| **Fail fast** | Validate config at startup and exit with an error | Typos are caught by the deploy itself. But a short DB outage at startup also kills the app |

The usual answer: **fail fast on things that are always wrong** (missing or malformed settings, using the Options pattern with `ValidateOnStart()`), but **don't** fail on things that can be temporarily unavailable (the database). That's the job of `/health`. Write down which category each of your settings belongs to.

---

## B. Health checks

### B1. Liveness vs readiness: one `/health` isn't enough

Your `/health` answers one question: *"Can this API serve requests right now, including its database?"* Orchestrators ask **two different** questions:

| Question | Name | If the answer is "no"… | Should it check the DB? |
|---|---|---|---|
| Is the process alive and not stuck? | **Liveness** | **Restart** the container | **No.** Restarting the API doesn't fix the database |
| Can it serve traffic right now? | **Readiness** | **Stop sending traffic** to it (don't restart) | **Yes** |

**Thought experiment:** the database goes down for 5 minutes. If the orchestrator uses your current `/health` (with the DB check) as a **liveness** check, it restarts every API container, again and again, all doing startup work while the DB is down: a **restart storm**. When the DB comes back, nothing is warm.

**Lab:** add both, and keep `/health` as it is (it's today's criterion):

```csharp
// Program.cs
using Microsoft.AspNetCore.Diagnostics.HealthChecks;

builder.Services.AddHealthChecks()
    .AddCheck<DatabaseHealthCheck>("database", tags: ["ready"]);

app.MapHealthChecks("/health");                                    // everything (as today)
app.MapHealthChecks("/health/live", new HealthCheckOptions
{
    Predicate = _ => false                                         // run no checks: "the process answers HTTP"
});
app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("ready")              // only checks tagged "ready"
});
```

Rebuild (`docker compose up -d --build api`), then `docker compose stop db`:

| Endpoint | DB up | DB stopped |
|---|---|---|
| `/health/live` | 200 | **200** |
| `/health/ready` | 200 | **503** |

**Why it matters (week 2):** App Runner's health check **replaces** instances that fail it, so it behaves like a liveness check. Which endpoint would you give it, and what happens during an RDS restart in each case? Write your answer in the log; you'll need it on 31/10.

### B2. Healthy, Degraded, Unhealthy

There's a third state. **Degraded** = "works, but something's wrong". By default it still returns **HTTP 200**, so traffic keeps flowing, but monitoring can alert on it.

**Lab:** mark the DB check Degraded when `SELECT 1` takes longer than 1 second:

```csharp
// DatabaseHealthCheck.CheckHealthAsync (inside the try)
var stopwatch = System.Diagnostics.Stopwatch.StartNew();
await using var connection = new SqlConnection(_connectionString);
await connection.OpenAsync(cancellationToken);
await using var command = new SqlCommand("SELECT 1", connection);
await command.ExecuteScalarAsync(cancellationToken);

return stopwatch.ElapsedMilliseconds > 1000
    ? HealthCheckResult.Degraded($"SQL Server is slow: {stopwatch.ElapsedMilliseconds} ms")
    : HealthCheckResult.Healthy("SQL Server is reachable.");
```

Test it by temporarily changing the query to `WAITFOR DELAY '00:00:02'; SELECT 1`. `/health` should say `Degraded` with status 200. **Revert the delay afterwards.**

### B3. See *why* it's unhealthy (safely)

`/health` only says `Unhealthy`, which is good for the public but useless for debugging. **Lab:** a detailed JSON version, **only in Development**:

```csharp
if (app.Environment.IsDevelopment())
{
    app.MapHealthChecks("/health/details", new HealthCheckOptions
    {
        ResponseWriter = (context, report) => context.Response.WriteAsJsonAsync(new
        {
            status = report.Status.ToString(),
            totalMs = report.TotalDuration.TotalMilliseconds,
            checks = report.Entries.Select(e => new
            {
                name = e.Key,
                status = e.Value.Status.ToString(),
                ms = e.Value.Duration.TotalMilliseconds,
                description = e.Value.Description,
                error = e.Value.Exception?.Message
            })
        })
    });
}
```

Stop `db` and open `/health/details`. You'll see the real SqlClient error. **Why only in Development?** Error messages leak server names, versions and network layout, which helps an attacker. In production, details go to **logs** (week 3: CloudWatch), never to an anonymous HTTP caller.

### B4. Solve your own mystery: 7.9 s, then 0 s

When you tested T4, the first `/health` after `stop db` took **7.9 s** (with `Connect Timeout=3`), and the next one took **0 s**. Investigate it like a real incident.

**Part 1, the 0 s:** SqlClient's connection pool has a **blocking period**. After a failed open, it remembers the error and fails new opens **immediately** for 5 s, then 10 s, 20 s… up to 1 minute. It's protection: it doesn't hammer a dead server.

Test it: add `;Pool Blocking Period=NeverBlock` to the health check's connection string (in `DatabaseHealthCheck`, `builder.PoolBlockingPeriod = PoolBlockingPeriod.NeverBlock`), rebuild, stop db, and call `/health` 3 times in a row. Every call should now take the full time.

Then decide: is fast-fail good for a health check? (Hint: who calls `/health`, and how often?)

**Part 2, the 7.9 s instead of 3 s:** form a hypothesis, then test. Compare two kinds of "database down":

```powershell
function Measure-Health { $sw=[Diagnostics.Stopwatch]::StartNew(); $r=Invoke-WebRequest http://localhost:5048/health -SkipHttpErrorCheck -TimeoutSec 60; "$($r.StatusCode) $($r.Content) $([math]::Round($sw.Elapsed.TotalSeconds,1))s" }

docker compose stop db;  Measure-Health; docker compose start db    # container gone: name "db" no longer resolves
# wait until db is healthy, then:
docker compose pause db; Measure-Health; docker compose unpause db  # container frozen: name resolves, nobody answers
```

The two failures look different from the network's point of view: **"no such host"** versus **"host exists but silent"**. Compare the times and check `docker compose logs api` for the exception messages. Write your conclusion in the log. In week 3 you'll pick alarm thresholds, and knowing how long failures take to surface is exactly that skill.

### B5. A health check for the API container itself?

`db` has a Compose `healthcheck`; `api` doesn't. **Lab:** check which tools the image has:

```powershell
docker compose exec api sh -c 'for t in curl wget bash; do command -v $t >/dev/null && echo "$t yes" || echo "$t no"; done'
```

**You'll see** `curl no`, `wget no`: the `aspnet` image is kept small on purpose. Your options:

| Option | Cost |
|---|---|
| `RUN apt-get install curl` in the Dockerfile | Bigger image, more CVEs to patch |
| Copy in a tiny static health-probe binary | One more thing to maintain |
| **Let the platform probe HTTP** (App Runner, ECS + load balancer, Kubernetes all call `/health` from outside) | Nothing: this is what you'll do in week 2 |

**Conclusion:** a container healthcheck for `api` is only worth it locally if another service needs `condition: service_healthy` on it. Here, nothing does.

### B6. "Unhealthy" does NOT restart anything

**Lab:** look at what Docker stores:

```powershell
docker inspect english-db --format '{{json .State.Health}}' | ConvertFrom-Json | Select-Object Status, FailingStreak, @{n='LastProbe';e={$_.Log[-1].Output}}
```

**Key fact:** plain Docker and Compose **only record** the health status. A container marked `unhealthy` keeps running, and nobody restarts it. Health status is used by:
- `depends_on: condition: service_healthy`, **at startup only**
- orchestrators (Docker Swarm, ECS, Kubernetes), which act on it

`restart:` policies react to the **process exiting**, not to health. Remember this difference in week 3 (alarms) and week 4 (deploys).

---

## C. Compose under the hood

### C1. How does the API find `db`?

```powershell
docker compose exec api sh -c 'cat /etc/resolv.conf; getent hosts db; getent hosts frontend'
```

**You'll see:**

```
nameserver 127.0.0.11
172.18.0.2      db
172.18.0.4      frontend
```

`127.0.0.11` is **Docker's built-in DNS server**, which exists on every user-defined network. Compose creates `english-learning_default` and registers every **service name** in it. That's why the connection string says `Server=db`. IPs change on every restart; names don't.

Try `docker network inspect english-learning_default` and find the three containers with their IPs.

### C2. `ports:` is a door to the outside, and it's open wider than you think

Your `docker-compose.yml` has `"14330:1433"`. Docker publishes that on **all network interfaces** (`0.0.0.0`):

```powershell
netstat -ano | Select-String ':14330 .*LISTENING'
```

**You'll see** `0.0.0.0:14330`: other devices on the same Wi-Fi or LAN may be able to reach your SQL Server at `<your-IP>:14330`, unless Windows Firewall blocks them. Only `sa`'s password stands in the way.

**Lab, two improvements:**

1. **Bind to localhost only**. DBeaver still works; other machines can't connect:

   ```yaml
   ports:
     - "127.0.0.1:${DB_PORT:-14330}:1433"
   ```

2. **Remove `ports:` from `db` entirely**, then `docker compose up -d`:
   - `/health` is still Healthy, because the API talks to `db:1433` **inside** the network.
   - DBeaver can't connect any more.

   Lesson: `ports:` is only for humans and tools **on your PC**. Containers never need it to talk to each other.

**Why it matters (week 2):** this is exactly "RDS in a private subnet, security group open only to the app". You're doing the same thing at Docker scale.

### C3. Look inside the volume

```powershell
docker volume inspect english-learning_sqldata
docker run --rm -v english-learning_sqldata:/data:ro alpine sh -c 'ls -la /data; ls -la /data/data | head'
```

**You'll see** SQL Server's folders (`data/`, `log/`, `secrets/`, `backup/`) and files like `EnglishVocabularyTraining.mdf`. They live inside Docker Desktop's Linux VM (`/var/lib/docker/volumes/...`), **not** in your project folder.

| Mount type | Example | Use for |
|---|---|---|
| **Named volume** | `sqldata:/var/opt/mssql` | Data that must survive containers (databases) |
| **Bind mount** | `./database:/scripts:ro` | Sharing **your** files with a container (scripts, config, live code) |
| `tmpfs` | `tmpfs: /tmp` | Throw-away data in RAM |

Question: why would a bind mount (`./sqldata:/var/opt/mssql`) be a bad idea for SQL Server on Windows? (Hint: file system speed and Linux file permissions across the Windows ↔ Linux VM boundary.)

### C4. `depends_on` only works at startup

**Lab:** restart the database **while the API keeps running**:

```powershell
docker compose restart db
1..10 | ForEach-Object { (Invoke-WebRequest http://localhost:5048/health -SkipHttpErrorCheck).StatusCode; Start-Sleep 3 }
```

**You'll see** `503 … 503 … 200`, and the API recovers **by itself, without a restart**. That works because the API opens a connection per request (ADO.NET pooling), rather than one connection held forever.

`depends_on` didn't help here: it only orders **startup**. After that, **your code** must survive dependencies coming and going. In the cloud, databases fail over, restart for patching, and scale; your app must reconnect on its own. (T5 adds `EnableRetryOnFailure`-style retries for the same reason.)

### C5. Restart policies

All your containers have `restart=no` (check: `docker inspect english-api --format '{{.HostConfig.RestartPolicy.Name}}'`).

**Lab:** add `restart: unless-stopped` to `api`, `docker compose up -d`, then make the app exit from inside:

```powershell
docker compose exec api kill 1        # PID 1 = dotnet; it exits as if stopped
docker compose ps api                 # watch the status / restart count
docker inspect english-api --format 'restarts={{.RestartCount}}'
```

| Policy | Restarts when… |
|---|---|
| `no` | never |
| `on-failure` | the process exits with a **non-zero** code |
| `always` | it exits for any reason (and when Docker starts) |
| `unless-stopped` | like `always`, but not if **you** stopped it with `docker stop` |

Bonus: with `unless-stopped` on all services, the stack comes back by itself after you restart your PC.

### C6. Graceful shutdown

```powershell
docker compose stop api
docker compose logs --tail 5 api
```

**You'll see** `Application is shutting down...`. Docker sent **SIGTERM**, ASP.NET finished in-flight requests and exited. Docker waits **10 s** (`stop_grace_period`), then sends SIGKILL.

This works because the Dockerfile uses the **exec form** `ENTRYPOINT ["dotnet", "Learning_EngLish.dll"]`. With the shell form (`ENTRYPOINT dotnet Learning_EngLish.dll`), `/bin/sh` is PID 1, it doesn't forward SIGTERM, and every stop takes the full 10 s and then kills the app mid-request. Try it if you're curious (change it, rebuild, time `docker compose stop api`, then revert).

**Why it matters (week 4):** every deploy and every auto-scaling "scale in" stops containers. Graceful shutdown = no failed requests during deploys.

### C7. Memory: measure, then limit

```powershell
docker stats --no-stream
```

Measured on your PC (21/10): `english-db` ≈ **705 MiB**, `english-api` ≈ **43 MiB**, `english-frontend` ≈ **21 MiB**.

**Lab:** give SQL Server too little memory and watch what happens:

```yaml
  db:
    mem_limit: 1g
```

`docker compose up -d db`, then `docker compose logs db`. SQL Server on Linux needs **at least 2 GB** and refuses to start. Set it to `2g` and it starts. Remove the limit when done; your data is safe in the volume either way.

**Why it matters (week 2):** RDS and App Runner sizes are **chosen and paid per hour by memory/CPU**. Measuring first and then picking a size is the habit you'll need for "chi phí theo giờ".

### C8. Small tools worth knowing

| Command / feature | What for |
|---|---|
| `docker compose config` | See the final merged file. Catches typos in `.env` and YAML |
| `docker compose events` | Live stream of what Compose is doing (start, die, health_status…) |
| `docker compose top` | Processes inside each container |
| `docker-compose.override.yml` | Personal changes (git-ignored), merged automatically |
| `profiles: [tools]` | Services that start only with `--profile tools` (for example a DB admin UI) |

---

## D. Scan your images

Docker Desktop includes **Docker Scout**:

```powershell
docker scout quickview english-api
docker scout cves english-api --only-severity critical,high
docker scout quickview english-api:alpine   # if you still have the T3 test image; otherwise rebuild it
```

Note the number of Critical/High CVEs. Compare `aspnet:10.0` with `alpine`/`chiseled` from T3: **smaller images usually have fewer CVEs**, because they contain fewer packages. In week 2, ECR's "scan on push" does the same thing, and you have to record those numbers (30/10).

---

## E. Read: 12-Factor App

https://12factor.net. Week 1's deep-dive list asks for **Config, Logs, Disposability**. Here they are, mapped to what you built:

| Factor | Says | In this project |
|---|---|---|
| **III. Config** | Config that varies per environment lives in the environment, not in code | `ConnectionStrings__DefaultConnection`, `.env`; same image everywhere |
| **IV. Backing services** | A database is an attached resource, swappable by config | PC SQL Server ↔ Docker `db` ↔ RDS (week 2) by changing one connection string |
| **IX. Disposability** | Start fast, shut down gracefully | Containers recreated freely (data in the volume); SIGTERM handling (C6) |
| **X. Dev/prod parity** | Keep dev and prod similar | SQL Server in Docker instead of a different DB locally |
| **XI. Logs** | Write logs to stdout; the platform collects them | `docker compose logs api` now, CloudWatch in week 3 |

Pick one factor your project **doesn't** follow yet, and write it in the log with how you'd fix it.

---

## F. Check yourself

Answer in `LEARNING_LOG.md` under T4, in your own words:

1. Why is `ConnectionStrings__DefaultConnection` in an environment variable better than in `appsettings.json`, and why is it still not good enough for production?
2. What's the difference between liveness and readiness? Which one should check the database?
3. A container is `unhealthy`. Does Docker restart it? What does?
4. Why can the API reach `db:1433` even after you remove `ports:` from `db`?
5. What does `depends_on: condition: service_healthy` guarantee, and what does it **not** guarantee?
6. What happens to your data on `docker compose down`? On `docker compose down -v`?
7. Your `/health` took 7.9 s the first time and 0 s the second time. Explain both numbers.
8. Why does the exec form of `ENTRYPOINT` matter for deploys?
