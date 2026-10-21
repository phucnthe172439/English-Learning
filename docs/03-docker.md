# 03 · Running the project on Docker

This guide explains how to build the **API** and the **frontend** into Docker images, run them as containers, update them after code changes, and push the images to a registry (Docker Hub or AWS ECR).

> **Current setup:** the API and the frontend run in Docker. **SQL Server stays on your PC** (it isn't containerized), and the API container connects to it.
>
> To run SQL Server in Docker too, with everything started by one `docker compose up`, see [04-database-docker.md](04-database-docker.md).

---

## 1. Docker in 2 minutes

Docker packages an app **together with everything it needs to run** (runtime, libraries, config), so it runs the same way on any machine. Nobody has to install .NET or Node to run the project; they only need Docker.

| Term | Meaning | Analogy |
|---|---|---|
| **Dockerfile** | Text recipe describing how to build the app | Recipe |
| **Image** | The built, read-only result of a Dockerfile | Frozen meal |
| **Container** | A running instance of an image (disposable) | Meal being served |
| **Port mapping** `-p 5048:8080` | `YOUR_PC_PORT:CONTAINER_PORT`: opens a door into the container | Door number |
| **Environment variable** `-e KEY=value` | Config passed into the container when it starts | Order notes |
| **Registry** | Online storage for images (Docker Hub, AWS ECR) | Warehouse |

Important: **a container never picks up code changes on its own.** After you change code, you rebuild the image and recreate the container (section 7).

---

## 2. Architecture

```
┌─────────────────────────── Your PC ────────────────────────────┐
│                                                                │
│   Browser                                                      │
│     │  http://localhost:4000            http://localhost:5048  │
│     ▼                                       ▼                  │
│  ┌───────────── Docker ────────────────────────────────────┐   │
│  │ ┌────────────────────────┐   ┌───────────────────────┐  │   │
│  │ │ english-frontend       │   │ english-api           │  │   │
│  │ │ Node 24 + Angular SSR  │   │ ASP.NET Core 10       │  │   │
│  │ │ listens on 4000        │   │ listens on 8080       │  │   │
│  │ └────────────────────────┘   └──────────┬────────────┘  │   │
│  └─────────────────────────────────────────┼───────────────┘   │
│                                            │ host.docker.internal:1433
│                                            ▼                   │
│                               SQL Server (installed on the PC) │
│                               DB: EnglishVocabularyTraining    │
└────────────────────────────────────────────────────────────────┘
```

| Container | Image | PC port → container port | Talks to |
|---|---|---|---|
| `english-api` | `english-api` | `5048 → 8080` | SQL Server on the PC through `host.docker.internal` |
| `english-frontend` | `english-frontend` | `4000 → 4000` | Nothing. The **browser** calls the API directly at `localhost:5048` |

---

## 3. Prerequisites (one-time setup)

### 3.1 Docker Desktop

1. Install **Docker Desktop for Windows**. Pick the **AMD64** or **ARM64** installer to match your PC (Settings → System → About → System type).
2. Docker needs the Windows features **Virtual Machine Platform** and **WSL**. If the installer complains, run this in an **administrator** PowerShell and restart:
   ```powershell
   wsl --install
   ```
3. If Docker still won't start, check that virtualization is enabled: Task Manager → Performance → CPU → **Virtualization: Enabled**. If it isn't, turn on Intel VT-x / AMD-V (SVM) in the BIOS.
4. Check that it works:
   ```powershell
   docker --version
   docker run hello-world      # should print "Hello from Docker!"
   ```

### 3.2 SQL Server must accept a SQL login

Containers run **Linux**, so they **can't** use Windows login (`Trusted_Connection=True`). SQL Server needs a username and password login, and it must accept TCP connections.

Run these in **DBeaver** (or SSMS) while connected as an admin:

**a) Check the login mode**
```sql
SELECT SERVERPROPERTY('IsIntegratedSecurityOnly') AS WindowsOnly;  -- 1 = Windows only
```

**b) Enable "SQL Server and Windows Authentication" mode** (only needed if (a) returned 1)
```sql
EXEC xp_instance_regwrite
    N'HKEY_LOCAL_MACHINE',
    N'Software\Microsoft\MSSQLServer\MSSQLServer',
    N'LoginMode', REG_DWORD, 2;
```

**c) Create a login for the app**
```sql
CREATE LOGIN english_app WITH PASSWORD = '<choose-a-strong-password>';

USE EnglishVocabularyTraining;
CREATE USER english_app FOR LOGIN english_app;
ALTER ROLE db_owner ADD MEMBER english_app;
```

**d) Enable TCP/IP**: open **SQL Server Configuration Manager** → SQL Server Network Configuration → Protocols for MSSQLSERVER → **TCP/IP → Enable**.

**e) Restart SQL Server**: in Configuration Manager → SQL Server Services → **SQL Server (MSSQLSERVER) → Restart**.

**f) Test it**: in DBeaver, create a new connection with **SQL Server Authentication** (`localhost`, port `1433`, user `english_app`, driver property `trustServerCertificate=true`). It should connect.

---

## 4. The Docker files in this repo

| File | Purpose |
|---|---|
| `WFMTTC_API/Learning_EngLish/Dockerfile` | Builds the API image |
| `WFMTTC_API/Learning_EngLish/.dockerignore` | Files left out of the API build (`bin/`, `obj/`, `.vs/`, …) |
| `FrontEnd/English_FrontEnd/Dockerfile` | Builds the frontend image |
| `FrontEnd/English_FrontEnd/.dockerignore` | Files left out of the frontend build (`node_modules/`, `dist/`, `.angular/`, …) |

### 4.1 API Dockerfile, explained

```dockerfile
# ---------- Stage 1: build ----------
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build   # big image with the .NET SDK (compiler)
WORKDIR /src
COPY Learning_EngLish.csproj .                    # copy only the project file first...
RUN dotnet restore                                # ...and download NuGet packages (cached!)
COPY . .                                          # then copy the source code
RUN dotnet publish -c Release -o /app --no-restore  # compile a Release build into /app

# ---------- Stage 2: run ----------
FROM mcr.microsoft.com/dotnet/aspnet:10.0         # small image: runtime only, no SDK
WORKDIR /app
COPY --from=build /app .                          # take ONLY the compiled output from stage 1
EXPOSE 8080                                       # ASP.NET in containers listens on 8080
USER $APP_UID                                     # run as the built-in non-root user "app" (uid 1654)
ENTRYPOINT ["dotnet", "Learning_EngLish.dll"]
```

**Why two stages?** The SDK is only needed to *compile*. The final image keeps only stage 2, so it's much smaller and has fewer tools an attacker could misuse.

**Why copy the `.csproj` first?** Docker caches each step. If only your `.cs` files change, the `dotnet restore` step is reused from cache and rebuilds are much faster.

### 4.2 Frontend Dockerfile, explained

```dockerfile
# ---------- Stage 1: build ----------
FROM node:24-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./   # package files first (cache trick again)
RUN npm ci                               # exact install from package-lock.json
COPY . .
RUN npm run build                        # ng build → /app/dist/English_FrontEnd/{browser,server}

# ---------- Stage 2: run ----------
FROM node:24-alpine
WORKDIR /app
COPY --from=build /app/package.json /app/package-lock.json ./
RUN npm ci --omit=dev                    # only runtime packages (no Angular CLI, TypeScript, …)
COPY --from=build /app/dist ./dist       # the built app
ENV PORT=4000
EXPOSE 4000
CMD ["node", "dist/English_FrontEnd/server/server.mjs"]   # start the SSR Express server
```

### 4.3 Why `.dockerignore` matters

Before building, Docker sends the whole folder (the **build context**) to the Docker engine. Without `.dockerignore`:
- `node_modules/` (hundreds of MB) would be sent on every build, which is slow,
- your local `bin/`/`obj/`/`dist/` could overwrite the fresh build inside the image,
- a `.env` file with real passwords could end up inside the image, readable by anyone who pulls it. Both `.dockerignore` files exclude `.env` and `.env.*`.

---

## 5. Code settings that make Docker work

These are already done. They're listed here so you know why they exist.

| Where | Setting | Why |
|---|---|---|
| `FrontEnd/.../src/app/services/api.config.ts` | `API_BASE_URL = 'http://localhost:5048/api'` | The API container is published on PC port 5048, over HTTP only |
| `WFMTTC_API/.../Program.cs` | CORS allows `http://localhost:4000` | Otherwise the browser blocks calls from the frontend container to the API |
| `FrontEnd/.../angular.json` | `"allowedHosts": ["localhost"]` | Otherwise the SSR server rejects every request: `Header "host" with value "localhost:4000" is not allowed.` |
| `docker run` for the API (not a file) | `ConnectionStrings__DefaultConnection=...` | Replaces the Windows-login connection string with a SQL login that works in Linux |

---

## 6. Build and run (first time)

Open **PowerShell**. Each `docker build` must be run **inside the folder that contains the Dockerfile**, because the `.` at the end means "this folder".

### Step 1: Build the API image

```powershell
cd C:\Mini-Project\WFMTTC\English-Learning\WFMTTC_API\Learning_EngLish
docker build -t english-api .
```
`-t english-api` names the image. The first build downloads the .NET images (about 1 GB) and takes a few minutes; later builds are faster.

### Step 2: Run the API container

> Stop the API in Visual Studio first if it's running, because it also uses port 5048.

```powershell
docker run -d --name english-api -p 5048:8080 `
  -e "ASPNETCORE_ENVIRONMENT=Development" `
  -e "ConnectionStrings__DefaultConnection=Server=host.docker.internal,1433;Database=EnglishVocabularyTraining;User Id=english_app;Password=<your-password>;TrustServerCertificate=True;" `
  english-api
```

| Part | Meaning |
|---|---|
| `-d` | Run in the background (detached) |
| `--name english-api` | Container name, used by `docker stop`, `docker logs` and so on |
| `-p 5048:8080` | PC port 5048 → container port 8080 |
| `ASPNETCORE_ENVIRONMENT=Development` | Turns on Swagger |
| `ConnectionStrings__DefaultConnection` | Overrides `appsettings.json` (`__` = one level of JSON nesting) |
| `host.docker.internal` | Special name that means "the PC Docker runs on", where SQL Server is |
| `` ` `` at line ends | PowerShell line continuation; you can also write it all on one line |

✅ Check: open **http://localhost:5048/swagger** and run `GET /api/Topic`.

### Step 3: Build the frontend image

```powershell
cd C:\Mini-Project\WFMTTC\English-Learning\FrontEnd\English_FrontEnd
docker build -t english-frontend .
```

### Step 4: Run the frontend container

```powershell
docker run -d --name english-frontend -p 4000:4000 english-frontend
```

✅ Check: open **http://localhost:4000**. The dashboard should show your words.

---

## 7. Updating after code changes

Containers are **disposable**: you don't edit them, you replace them. After changing code:

### API changed
```powershell
cd C:\Mini-Project\WFMTTC\English-Learning\WFMTTC_API\Learning_EngLish
docker rm -f english-api                 # 1. delete the old container
docker build -t english-api .            # 2. rebuild the image with the new code
docker run -d --name english-api ...     # 3. run again (same command as step 2)
```

### Frontend changed
```powershell
cd C:\Mini-Project\WFMTTC\English-Learning\FrontEnd\English_FrontEnd
docker rm -f english-frontend
docker build -t english-frontend .
docker run -d --name english-frontend -p 4000:4000 english-frontend
```

Then press **Ctrl + F5** in the browser to skip its cache.

> **Which one should I rebuild?** Only the part you changed. A change to `Program.cs` → rebuild the API. A change under `src/` or to `angular.json` → rebuild the frontend.

### Day-to-day (no code changes)

```powershell
docker stop english-api english-frontend     # stop both (for example at the end of the day)
docker start english-api english-frontend    # start them again
```
You can also use the ▶ / ■ buttons in Docker Desktop → **Containers**.

---

## 8. Useful commands

| Command | What it does |
|---|---|
| `docker ps` | Running containers |
| `docker ps -a` | All containers, including stopped ones |
| `docker images` | Images on your PC |
| `docker logs english-api` | Container output (add `-f` to follow it live) |
| `docker exec -it english-api bash` | Open a shell inside the container (use `sh` for the frontend, since Alpine has no bash) |
| `docker stop <name>` / `docker start <name>` | Stop / start a container |
| `docker rm -f <name>` | Delete a container |
| `docker rmi <image>` | Delete an image |
| `docker system df` | How much disk space Docker uses |
| `docker image prune` | Delete unused (dangling) images left behind by rebuilds |
| `docker system prune` | Clean up stopped containers, unused networks and dangling images |

---

## 9. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `failed to read dockerfile: open Dockerfile: no such file or directory` | You ran `docker build` from the wrong folder | `cd` into the folder that contains the `Dockerfile`, or pass the path: `docker build -t english-api C:\...\Learning_EngLish` |
| `Bind for 0.0.0.0:5048 failed: port is already allocated` | Something else uses the port (often the API running in Visual Studio, or an old container) | Stop Visual Studio's run or `docker rm -f english-api`, or map another port: `-p 5050:8080` |
| `Conflict. The container name "/english-api" is already in use` | A container with that name already exists | `docker rm -f english-api`, then run again |
| Swagger works, but endpoints return **500** | The API can't reach SQL Server | `docker logs english-api`. Check section 3.2: SQL login enabled, TCP/IP on, SQL Server restarted, password correct |
| `Login failed for user 'english_app'` | Wrong password, or SQL login mode not enabled | Repeat 3.2 (b) and restart SQL Server |
| `A network-related or instance-specific error` | TCP/IP disabled, or the firewall blocks 1433 | Enable TCP/IP (3.2 d), then allow port 1433 in Windows Firewall |
| Page shows `Header "host" with value "..." is not allowed` | Host missing from `allowedHosts` | Add it in `angular.json` and rebuild, or run with `-e "NG_ALLOWED_HOSTS=localhost,<your-host>"` |
| Dashboard: "Cannot reach the API at …" | API not running, wrong `API_BASE_URL`, or CORS | Is http://localhost:5048/swagger reachable? Press F12 → Console. A **CORS** error means: add the origin in `Program.cs` and rebuild the API |
| Code change doesn't show up | The old image or container is still running | Rebuild **and** recreate the container (section 7), then Ctrl + F5 |
| `docker build` fails at `npm ci` | `package-lock.json` is out of sync with `package.json` | Run `npm install` locally, commit `package-lock.json`, rebuild |

---

## 10. Pushing images to a registry ("uploading")

So far, the images exist **only on your PC**. To share them with teammates or deploy them to a server, push them to a **registry**.

### 10.1 Docker Hub

1. Create an account at https://hub.docker.com.
2. Log in from PowerShell:
   ```powershell
   docker login
   ```
3. **Tag** the images with your Docker Hub username and a version:
   ```powershell
   docker tag english-api      <dockerhub-user>/english-api:1.0
   docker tag english-frontend <dockerhub-user>/english-frontend:1.0
   ```
4. **Push**:
   ```powershell
   docker push <dockerhub-user>/english-api:1.0
   docker push <dockerhub-user>/english-frontend:1.0
   ```
5. On any other machine:
   ```powershell
   docker pull <dockerhub-user>/english-api:1.0
   docker run -d --name english-api -p 5048:8080 -e "ConnectionStrings__DefaultConnection=..." <dockerhub-user>/english-api:1.0
   ```

> Docker Hub repositories are **public by default**. Make them **private** in the Docker Hub settings if the code shouldn't be public. Passwords aren't inside the image (they're passed with `-e` at run time), which is exactly why we keep it that way.

### 10.2 AWS ECR (for the AWS deployment)

ECR is AWS's private registry. It's where the images go before running them on **ECS / App Runner / EC2**. You need the AWS CLI installed and configured (`aws configure`).

```powershell
# Variables
$REGION  = "ap-southeast-1"          # pick your region
$ACCOUNT = "<aws-account-id>"
$REGISTRY = "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"

# 1. Create the repositories (once)
aws ecr create-repository --repository-name english-api      --region $REGION
aws ecr create-repository --repository-name english-frontend --region $REGION

# 2. Log Docker in to ECR
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REGISTRY

# 3. Tag and push
docker tag english-api      "$REGISTRY/english-api:1.0"
docker tag english-frontend "$REGISTRY/english-frontend:1.0"
docker push "$REGISTRY/english-api:1.0"
docker push "$REGISTRY/english-frontend:1.0"
```

### 10.3 Things to change before a real deployment

| Item | Local value | For the cloud |
|---|---|---|
| Database | SQL Server on your PC (`host.docker.internal`) | AWS **RDS for SQL Server** → put its endpoint in `ConnectionStrings__DefaultConnection` |
| `API_BASE_URL` (`api.config.ts`) | `http://localhost:5048/api` | The public API URL (for example `https://api.myapp.com/api`) → rebuild the frontend |
| CORS (`Program.cs`) | `localhost:4200`, `localhost:4000` | Add the public frontend URL → rebuild the API |
| Allowed hosts | `localhost` | `-e "NG_ALLOWED_HOSTS=myapp.com"` on the frontend container |
| `ASPNETCORE_ENVIRONMENT` | `Development` (Swagger on) | Leave it unset (`Production`) |
| Secrets | Typed into `docker run` | AWS Secrets Manager / task environment variables, never committed to Git |
| Image architecture | Your PC's (AMD64 or ARM64) | Must match the server. Build for a specific one with `docker build --platform linux/amd64 ...` |

---

## 11. Next step: Docker Compose

Typing two long `docker run` commands gets tiring. **Docker Compose** describes all containers in one `docker-compose.yml` file, so the whole project starts with:

```powershell
docker compose up -d --build    # build + start everything
docker compose down             # stop and remove everything
```

> **Done:** `docker-compose.yml` now exists at the repo root and also includes SQL Server. See [04-database-docker.md](04-database-docker.md). The sketch below is the original plan.

Planned layout:

```yaml
services:
  api:
    build: ./WFMTTC_API/Learning_EngLish
    ports: ["5048:8080"]
    environment:
      ASPNETCORE_ENVIRONMENT: Development
      ConnectionStrings__DefaultConnection: ${DB_CONNECTION}   # read from a .env file (git-ignored)
  frontend:
    build: ./FrontEnd/English_FrontEnd
    ports: ["4000:4000"]
    depends_on: [api]
```

The password would live in a local `.env` file, which is already in `.gitignore`.
