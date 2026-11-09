<#
Builds, pushes and deploys the API and/or frontend to ECS Fargate.
Run setup.ps1 once before the first deploy. Docker Desktop must be running.

Usage (from the repo root):
  ./deploy/ecs/deploy.ps1 -Tag 1.1                  # build + push both images as 1.1, then deploy them
  ./deploy/ecs/deploy.ps1 -Tag 1.2 -Only frontend   # only one service
  ./deploy/ecs/deploy.ps1 -Tag 1.1 -Only api        # rollback: a tag already in ECR is deployed without rebuilding

A failed deployment (tasks that never become healthy) is rolled back automatically by ECS (circuit breaker).
#>
param(
    [Parameter(Mandatory)] [string] $Tag,
    [ValidateSet('all', 'api', 'frontend')] [string] $Only = 'all'
)
. "$PSScriptRoot/config.ps1"
$repoRoot = Resolve-Path "$PSScriptRoot/../.."

$services = @(
    if ($Only -in 'all', 'api') { $Api }
    if ($Only -in 'all', 'frontend') { $Frontend }
)

$execRoleArn = aws iam get-role --role-name $ExecRole --query Role.Arn --output text
$secretArn   = aws secretsmanager describe-secret --secret-id $DbSecretName --query ARN --output text
$ecsSg       = Get-SecurityGroupId $EcsSgName
$albDns      = Get-AlbDnsName

# ---------- 1. Images: build and push unless the tag is already in ECR ----------
$loggedIn = $false
foreach ($svc in $services) {
    $image = "$Registry/$($svc.Repo):$Tag"
    $inEcr = aws ecr describe-images --repository-name $svc.Repo `
        --query "imageDetails[?contains(imageTags || ``[]``, '$Tag')] | length(@)" --output text
    if ($inEcr -ne '0') {
        Write-Host "Image $image already in ECR, not rebuilding"
        continue
    }
    if (-not $loggedIn) {
        aws ecr get-login-password | docker login --username AWS --password-stdin $Registry
        $loggedIn = $true
    }
    # Fargate tasks below run on x86_64
    docker build --platform linux/amd64 -t $image (Join-Path $repoRoot $svc.BuildContext)
    docker push $image
}

# ---------- 2. Task definitions ----------
function Get-TaskDefinition($svc) {
    $container = @{
        name = $svc.Container
        image = "$Registry/$($svc.Repo):$Tag"
        essential = $true
        portMappings = @(@{ containerPort = $svc.Port; protocol = 'tcp' })
        logConfiguration = @{
            logDriver = 'awslogs'
            options = @{ 'awslogs-group' = $svc.LogGroup; 'awslogs-region' = $Region; 'awslogs-stream-prefix' = $svc.Container }
        }
    }
    if ($svc.Service -eq $Api.Service) {
        $container.environment = @(@{ name = 'ASPNETCORE_ENVIRONMENT'; value = 'Production' })
        # Each key of the secret becomes one env var; Program.cs builds the connection string from them.
        # Only the secret's ARN is stored in the task definition, never the password.
        $container.secrets = @(
            @{ name = 'Database__Host';     valueFrom = "${secretArn}:host::" }
            @{ name = 'Database__Port';     valueFrom = "${secretArn}:port::" }
            @{ name = 'Database__Name';     valueFrom = "${secretArn}:dbname::" }
            @{ name = 'Database__User';     valueFrom = "${secretArn}:username::" }
            @{ name = 'Database__Password'; valueFrom = "${secretArn}:password::" }
        )
    } else {
        $container.environment = @(
            @{ name = 'PORT'; value = "$($svc.Port)" }
            # Angular SSR only renders requests whose Host header is in this list
            @{ name = 'NG_ALLOWED_HOSTS'; value = $albDns }
        )
    }
    @{
        family = $svc.Service
        networkMode = 'awsvpc'
        requiresCompatibilities = @('FARGATE')
        cpu = '256'           # 0.25 vCPU
        memory = '512'        # MiB
        runtimePlatform = @{ cpuArchitecture = 'X86_64'; operatingSystemFamily = 'LINUX' }
        executionRoleArn = $execRoleArn
        containerDefinitions = @($container)
    }
}

# ---------- 3. Services: create on first deploy, update afterwards ----------
foreach ($svc in $services) {
    $taskDefArn = aws ecs register-task-definition --cli-input-json (ConvertTo-AwsJsonFile (Get-TaskDefinition $svc)) `
        --query taskDefinition.taskDefinitionArn --output text
    Write-Host "Task definition: $taskDefArn"

    $status = aws ecs describe-services --cluster $Cluster --services $svc.Service --query 'services[0].status' --output text
    if ($status -eq 'ACTIVE') {
        aws ecs update-service --cluster $Cluster --service $svc.Service --task-definition $taskDefArn | Out-Null
        Write-Host "Service $($svc.Service): updating"
    } else {
        $tgArn = aws elbv2 describe-target-groups --names $svc.TargetGroup --query 'TargetGroups[0].TargetGroupArn' --output text
        $network = @{ awsvpcConfiguration = @{ subnets = $Subnets; securityGroups = @($ecsSg); assignPublicIp = 'ENABLED' } }
        $lb = @(@{ targetGroupArn = $tgArn; containerName = $svc.Container; containerPort = $svc.Port })
        aws ecs create-service --cluster $Cluster --service-name $svc.Service --task-definition $taskDefArn `
            --desired-count 1 --launch-type FARGATE `
            --network-configuration (ConvertTo-AwsJsonFile $network) `
            --load-balancers (ConvertTo-AwsJsonFile $lb) `
            --health-check-grace-period-seconds 60 `
            --deployment-configuration 'deploymentCircuitBreaker={enable=true,rollback=true},minimumHealthyPercent=100,maximumPercent=200' | Out-Null
        Write-Host "Service $($svc.Service): created"
    }
}

# ---------- 4. Wait until the new tasks are healthy behind the ALB ----------
Write-Host 'Waiting for the services to become stable (a few minutes)...'
aws ecs wait services-stable --cluster $Cluster --services ($services | ForEach-Object { $_.Service })
Write-Host ''
Write-Host "Done. App: http://$albDns"
Write-Host "Logs: aws logs tail $($Api.LogGroup) --follow   (or $($Frontend.LogGroup))"
