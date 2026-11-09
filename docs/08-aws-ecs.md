# 08 · Run on AWS ECS (Fargate) + CI/CD with GitHub Actions

This replaces the EC2 setup of [07](07-aws-ec2-rds.md). The database stays on **RDS `database-1`** (SQL Server) and the secret `english-learning/prod/db` stays as it is. Redis is not deployed: the API only uses it on the `/redis-test` endpoint.

Account `563250343209`, region **ap-southeast-1** (Singapore). Check the region in the top-right corner of the console before every step.

```
Internet --:80--> Load balancer (english-alb)
                    |-- /api/*  --> ECS service english-api       (container :8080) --:1433--> RDS database-1
                    '-- other    --> ECS service english-frontend  (container :4000)
```

Everything is created by the scripts in [deploy/ecs/](../deploy/ecs/):

| Script | What it does | When |
|---|---|---|
| `setup.ps1` | Security groups, IAM execution role, log groups, ECS cluster, load balancer | Once (safe to re-run) |
| `init-db.ps1` | Runs `database/init-db.sh` on RDS as a one-off ECS task: schema, seed, `english_app` login | Once, and after changing the DB password |
| `deploy.ps1 -Tag <ver>` | Builds and pushes images, creates or updates both services, waits until healthy | Every release |

Run them from the repo root in **PowerShell 7**, with Docker Desktop running:
`pwsh -ExecutionPolicy Bypass -File .\deploy\ecs\<script>.ps1`

---

## A. Set up a new PC (once per PC)

You need this only to run the scripts by hand. CI/CD (section 4) needs nothing on your PC.

1. **Install the tools** (PowerShell, one line each; then open a **new** terminal):
   ```powershell
   winget install Git.Git
   winget install Docker.DockerDesktop
   winget install Amazon.AWSCLI
   winget install Microsoft.PowerShell
   ```
   Start **Docker Desktop** once and wait for **Engine running**.
2. **Get the code:**
   ```powershell
   git clone https://github.com/phucnthe172439/English-Learning.git
   cd English-Learning
   git checkout develop
   ```
3. **Sign in to AWS.** Ask the account owner for an **IAM user** with an access key (do not use root keys), then:
   ```powershell
   aws configure
   ```
   Enter the access key ID, the secret access key, region `ap-southeast-1`, output `json`. (If your team uses SSO: `aws sso login` instead.)
4. **Check everything** (open PowerShell 7 with `pwsh`):
   ```powershell
   docker info --format "{{.ServerVersion}}"   # a version number
   aws sts get-caller-identity                 # "Account": "563250343209"
   ```

## B. First-time deploy, step by step

Skip B2-B3 if the AWS resources already exist (check: ECS → Clusters shows `english-learning`). Run every command in `pwsh`, in the repo root.

**B1. RDS must be running.** Console → **RDS → Databases → database-1**: status **Available**. If **Stopped**, click **Actions → Start** and wait 5-10 minutes.

**B2. Create the AWS resources** (about 1 minute; safe to re-run):
```powershell
pwsh -ExecutionPolicy Bypass -File .\deploy\ecs\setup.ps1
```
Expected: lines such as `ECR: ... created`, `SG: ... exists`, `ECS: cluster english-learning ready`, and at the end `Setup done. Load balancer: http://english-alb-...`.

**B3. Create or repair the database** (3-8 minutes the first time):
```powershell
pwsh -ExecutionPolicy Bypass -File .\deploy\ecs\init-db.ps1
```
Expected: between the dashed lines `Creating/updating the english_app login...`, and a green `Database is ready.`

**B4. Build, push and deploy** (5-10 minutes; use a version nobody used yet):
```powershell
pwsh -ExecutionPolicy Bypass -File .\deploy\ecs\deploy.ps1 -Tag 1.0
```
Expected: it ends with `Done. App: http://english-alb-...`.

**B5. Verify** in the console: section 1 below.

Later releases: `deploy.ps1 -Tag <new version>`; one service only: add `-Only api` or `-Only frontend`. Normally CI/CD (section 4) does this for you on every merge to `main`.

Scripts fail to run with *"running scripts is disabled"*? You used Windows PowerShell 5.1. Use `pwsh` and the `-ExecutionPolicy Bypass -File` form above.

---

## 1. Check that it works (AWS console)

**Services running**
1. Search `ECS` → **Clusters** → **english-learning** → **Services** tab.
2. Both `english-api` and `english-frontend` show **Active**, tasks **1/1**, deployment **Completed**.

**Load balancer considers them healthy**
1. Search `EC2` → left menu **Target Groups**.
2. Open `english-api-tg` → **Targets** tab: status **Healthy**. Same for `english-frontend-tg`.

**App in the browser**
1. EC2 → **Load Balancers** → `english-alb` → copy the **DNS name**.
2. Open `http://<DNS name>` (`http`, not `https`).
3. The word list shows. Add a word, edit it, delete it: this proves the API can write to RDS.

**Logs**: CloudWatch → **Log groups** → `/ecs/english-api` or `/ecs/english-frontend` → newest log stream.

---

## 2. Troubleshooting

| What you see | Cause | Fix |
|---|---|---|
| `english-api-tg` target **Unhealthy** `[503]`, API log says `Login failed for user 'english_app'` | The `english_app` login on RDS does not match the password in the secret | Section 3 |
| `english-frontend-tg` target **Unhealthy** `[400]`, log says `Header "host" ... is not allowed` | Old frontend image without `/healthz` | Deploy a new frontend tag |
| ECS event `ResourceInitializationError ... secrets` | The execution role cannot read a secret | Re-run `setup.ps1` |
| API log says `Cannot open database "EnglishVocabularyTraining"` | The database does not exist yet | Run `init-db.ps1` |
| Deploy script ends with `Waiter ServicesStable failed` | New tasks did not become healthy; ECS rolled back | Read the API log (above) |

## 3. Fix `Login failed for user 'english_app'` (console only)

Cause seen in this project: the password in the secret contained `{ ] = . _`; use **letters and digits only**.

**A. Change the password in Secrets Manager**
1. Search `Secrets Manager` → **english-learning/prod/db** → **Retrieve secret value** → **Edit**.
2. Replace the value of the **`password`** row with 24 letters and digits. Leave the other rows alone. **Save**.

**B. Apply it to the database (run the init task)**
1. **ECS → Task definitions → english-db-init →** revision **1 → Deploy → Run task**.
2. **Existing cluster** `english-learning`; compute option **Launch type: FARGATE**.
3. Networking: default VPC; keep all subnets; **Use an existing security group** → `english-ecs-sg` (remove `default`); **Public IP: Turned on**.
4. **Create**. In the cluster's **Tasks** tab refresh until the task is **Stopped** (1-3 minutes).
5. Click the task → **Containers** → **Exit code 0**. If not, read the **Logs** tab.

**C. Restart the API**
1. **ECS → Clusters → english-learning → Services → english-api → Update**.
2. Tick **Force new deployment** → **Update**. Wait until the deployment is **Completed**.

---

## 4. CI/CD with GitHub Actions

Goal: when you merge into `main`, GitHub builds both images, pushes them to ECR (tag = commit SHA) and updates the ECS services. The workflow is [.github/workflows/deploy-ecs.yml](../.github/workflows/deploy-ecs.yml) and it runs the same `deploy.ps1` you run by hand.

GitHub signs in to AWS with **OIDC**: AWS trusts tokens issued by GitHub for **this repo and the `main` branch only**, so **no access keys are stored in GitHub**. Pull requests and other branches cannot deploy.

Do the steps in order. Steps 4.1-4.3 are in the AWS console, 4.4 in GitHub.

### 4.1 Make AWS trust GitHub (once per AWS account)
1. AWS console → search `IAM` → left menu **Identity providers** → **Add provider**.
2. **Provider type:** OpenID Connect.
3. **Provider URL:** `https://token.actions.githubusercontent.com` → click **Get thumbprint**.
4. **Audience:** `sts.amazonaws.com`.
5. **Add provider**.

If it says the provider already exists, that is fine: skip to 4.2.

### 4.2 Create the role GitHub will use
1. IAM → **Roles** → **Create role**.
2. **Trusted entity type:** Custom trust policy. Delete the text and paste the whole content of [deploy/ecs/github-trust-policy.json](../deploy/ecs/github-trust-policy.json). Check the `sub` line: `repo:phucnthe172439/English-Learning:ref:refs/heads/main` (change it if your GitHub user or repo name differs; it is case-sensitive).
3. **Next** → on "Add permissions" click **Next** without selecting anything.
4. **Role name:** `english-github-deploy-role` → **Create role**.

### 4.3 Give the role its permissions
1. IAM → **Roles** → open `english-github-deploy-role`.
2. **Add permissions → Create inline policy** → tab **JSON**. Delete the text and paste the content of [deploy/ecs/github-deploy-policy.json](../deploy/ecs/github-deploy-policy.json).
3. **Next** → **Policy name:** `deploy-english-ecs` → **Create policy**.
4. On the role page, copy the **ARN** at the top. It looks like `arn:aws:iam::563250343209:role/english-github-deploy-role`.

The policy allows only: push/pull to the two ECR repositories, register task definitions, update services, pass the execution role to ECS, and the read-only lookups the script needs. It cannot delete anything.

### 4.4 Tell GitHub which role to use
1. GitHub → your repo → **Settings → Secrets and variables → Actions → Variables** tab → **New repository variable**.
2. **Name:** `AWS_DEPLOY_ROLE_ARN`. **Value:** the ARN from 4.3. **Add variable**.

(This is a variable, not a secret: the ARN is not sensitive.)

### 4.5 Get the workflow onto `main`
The workflow only runs from `main`. Commit the new files on `develop`, push, then open a pull request **develop → main** on GitHub and merge it. The merge triggers the first deployment.

### 4.6 Watch a deployment
1. GitHub → **Actions** tab → **Deploy to ECS** → click the newest run.
2. Click the job **deploy**. Expand the steps: **Who am I** must show `.../english-github-deploy-role/...`; **Build, push and deploy** takes 8-15 minutes.
3. Green check = both services updated and healthy. Verify as in section 1.

Run it by hand without a code change: **Actions → Deploy to ECS → Run workflow** → branch **main**.

### 4.7 Roll back
- **Quick:** Actions → pick an older successful run → **Re-run all jobs**. That commit's images are still in ECR, so it redeploys them without rebuilding.
- **From your PC:** `deploy.ps1 -Tag <old commit sha> -Only api` (ECR → `english-api` shows the tags).

If a deployment fails, ECS keeps the old tasks running (circuit breaker), so the site stays up.

### 4.8 CI/CD troubleshooting

| Error in the Actions log | Cause | Fix |
|---|---|---|
| `Credentials could not be loaded` / `Could not assume role` / `Not authorized to perform sts:AssumeRoleWithWebIdentity` | Trust policy does not match (wrong repo name, wrong branch, provider missing), or `AWS_DEPLOY_ROLE_ARN` is empty | Re-check 4.1, the `sub` line in 4.2, and the variable name in 4.4. Runs from `develop` or a pull request are rejected on purpose. |
| `AccessDenied` on `ecr:...`, `ecs:...` or `iam:PassRole` | A permission is missing in the inline policy | Read which action the error names, add it in 4.3 |
| Step fails at `docker build` | Code error | Fix it and push again |
| `Waiter ServicesStable failed` | New tasks unhealthy; ECS rolled back | Read `/ecs/english-api` logs (section 1) |

### 4.9 Good to know
- `setup.ps1` and `init-db.ps1` are **not** run by CI. They change infrastructure and the database, so run them yourself when needed.
- Each run builds both images (about 8-15 minutes). It is simple on purpose; splitting by changed folder can come later.
- Only `main` deploys. To require a pull request and review before `main` changes: GitHub → **Settings → Branches → Add branch ruleset** for `main`.
- Cost of CI: GitHub Actions minutes are free for public repos and have a monthly free quota for private ones.

---

## 5. Cost and cleaning up

Running full time: roughly **$40/month** (load balancer ~$20, two small Fargate tasks ~$10 each, plus RDS).

To pause: **ECS → Services → select a service → Update → Desired tasks = 0** (both services), and **RDS → database-1 → Actions → Stop temporarily**. The load balancer keeps charging until deleted.

Left over from the EC2 setup, safe to remove once ECS works: the `EC2Test` instance, the `launch-wizard-1` rule on `english-rds-sg`, and the stopped Aurora PostgreSQL cluster `database-1` if unused.
