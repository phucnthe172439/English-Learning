<#
Creates or repairs the database on RDS by running database/init-db.sh as a one-off ECS task
(RDS is private, so it can't be reached from your PC). Same rules as db-init in docker-compose.yml:
  no tables -> create schema; empty tables -> seed; existing data -> left alone;
  always -> create the english_app login or reset its password to the one in the secret.
Safe to re-run, e.g. after changing the password in Secrets Manager.

Usage (from the repo root, Docker Desktop running):   pwsh -File ./deploy/ecs/init-db.ps1
#>
. "$PSScriptRoot/config.ps1"
$repoRoot = Resolve-Path "$PSScriptRoot/../.."

$execRoleArn  = aws iam get-role --role-name $ExecRole --query Role.Arn --output text
$appSecretArn = aws secretsmanager describe-secret --secret-id $DbSecretName --query ARN --output text
$masterSecret = aws rds describe-db-instances --db-instance-identifier $RdsInstance `
    --query 'DBInstances[0].MasterUserSecret.SecretArn' --output text
$ecsSg = Get-SecurityGroupId $EcsSgName

# ---------- 1. Image (docker reuses its cache, so re-runs are quick) ----------
$image = "$Registry/$($DbInit.Repo):latest"
aws ecr get-login-password | docker login --username AWS --password-stdin $Registry
docker build --platform linux/amd64 -t $image (Join-Path $repoRoot $DbInit.BuildContext)
docker push $image

# ---------- 2. Task definition: passwords come straight from Secrets Manager ----------
$taskDef = @{
    family = $DbInit.Family
    networkMode = 'awsvpc'
    requiresCompatibilities = @('FARGATE')
    cpu = '256'; memory = '1024'
    runtimePlatform = @{ cpuArchitecture = 'X86_64'; operatingSystemFamily = 'LINUX' }
    executionRoleArn = $execRoleArn
    containerDefinitions = @(@{
        name = $DbInit.Container
        image = $image
        essential = $true
        secrets = @(
            @{ name = 'DB_HOST';           valueFrom = "${appSecretArn}:host::" }
            @{ name = 'APP_DB_PASSWORD';   valueFrom = "${appSecretArn}:password::" }
            @{ name = 'DB_ADMIN_USER';     valueFrom = "${masterSecret}:username::" }
            @{ name = 'MSSQL_SA_PASSWORD'; valueFrom = "${masterSecret}:password::" }
        )
        logConfiguration = @{
            logDriver = 'awslogs'
            options = @{ 'awslogs-group' = $DbInit.LogGroup; 'awslogs-region' = $Region; 'awslogs-stream-prefix' = 'db-init' }
        }
    })
}
$taskDefArn = aws ecs register-task-definition --cli-input-json (ConvertTo-AwsJsonFile $taskDef) `
    --query taskDefinition.taskDefinitionArn --output text

# ---------- 3. Run once and wait ----------
$network = @{ awsvpcConfiguration = @{ subnets = $Subnets; securityGroups = @($ecsSg); assignPublicIp = 'ENABLED' } }
$taskArn = aws ecs run-task --cluster $Cluster --task-definition $taskDefArn --launch-type FARGATE `
    --network-configuration (ConvertTo-AwsJsonFile $network) --query 'tasks[0].taskArn' --output text
Write-Host "Started $taskArn, waiting for it to finish (pulling the SQL Server image takes 1-3 minutes)..."
aws ecs wait tasks-stopped --cluster $Cluster --tasks $taskArn

# ---------- 4. Result ----------
$result = aws ecs describe-tasks --cluster $Cluster --tasks $taskArn `
    --query 'tasks[0].{exit:containers[0].exitCode,reason:stoppedReason}' --output json | ConvertFrom-Json
$taskId = ($taskArn -split '/')[-1]
Write-Host '---------- output ----------'
aws logs get-log-events --log-group-name $DbInit.LogGroup --log-stream-name "db-init/$($DbInit.Container)/$taskId" `
    --query 'events[].message' --output text
Write-Host '----------------------------'
if ($result.exit -eq 0) {
    Write-Host 'Database is ready.' -ForegroundColor Green
} else {
    Write-Host "db-init failed (exit code: $($result.exit), reason: $($result.reason))" -ForegroundColor Red
    exit 1
}
