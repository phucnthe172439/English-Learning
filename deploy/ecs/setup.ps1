<#
One-time setup of the AWS resources for running English-Learning on ECS Fargate:
  ECR repo for the frontend, security groups, IAM execution role, log groups,
  ECS cluster, Application Load Balancer with two target groups.
Safe to re-run: each step skips what already exists.

Usage (from the repo root):   ./deploy/ecs/setup.ps1
Then deploy the containers:   ./deploy/ecs/deploy.ps1 -Tag 1.1

    Internet --:80--> ALB (english-alb-sg)
                       |-- /api/*  --> english-api service      :8080 --:1433--> RDS database-1
                       '-- else    --> english-frontend service :4000
#>
. "$PSScriptRoot/config.ps1"

# ---------- 1. ECR repository for the frontend (english-api already exists) ----------
foreach ($repo in $Api.Repo, $Frontend.Repo, $DbInit.Repo) {
    $exists = aws ecr describe-repositories --query "repositories[?repositoryName=='$repo'] | length(@)" --output text
    if ($exists -eq '0') {
        aws ecr create-repository --repository-name $repo --image-scanning-configuration scanOnPush=true | Out-Null
        Write-Host "ECR: created $repo"
    } else { Write-Host "ECR: $repo exists" }
}

# ---------- 2. Security groups ----------
$albSg = Get-SecurityGroupId $AlbSgName
if ($albSg -eq 'None') {
    $albSg = aws ec2 create-security-group --group-name $AlbSgName --vpc-id $VpcId `
        --description 'English-Learning ALB: HTTP from the internet' --query GroupId --output text
    aws ec2 authorize-security-group-ingress --group-id $albSg --protocol tcp --port 80 --cidr 0.0.0.0/0 | Out-Null
    Write-Host "SG: created $AlbSgName ($albSg)"
} else { Write-Host "SG: $AlbSgName exists ($albSg)" }

$ecsSg = Get-SecurityGroupId $EcsSgName
if ($ecsSg -eq 'None') {
    $ecsSg = aws ec2 create-security-group --group-name $EcsSgName --vpc-id $VpcId `
        --description 'English-Learning ECS tasks: only from the ALB' --query GroupId --output text
    # Tasks accept traffic only from the ALB, on the two container ports
    $rules = foreach ($port in $Api.Port, $Frontend.Port) {
        @{ IpProtocol = 'tcp'; FromPort = $port; ToPort = $port; UserIdGroupPairs = @(@{ GroupId = $albSg }) }
    }
    aws ec2 authorize-security-group-ingress --group-id $ecsSg --ip-permissions (ConvertTo-AwsJsonFile @($rules)) | Out-Null
    Write-Host "SG: created $EcsSgName ($ecsSg)"
} else { Write-Host "SG: $EcsSgName exists ($ecsSg)" }

# RDS accepts 1433 from the ECS tasks (the existing rule for the EC2 SG is left as is)
$rdsRule = aws ec2 describe-security-groups --group-ids $RdsSgId `
    --query "SecurityGroups[0].IpPermissions[?FromPort==``1433``].UserIdGroupPairs[].GroupId | contains(@, '$ecsSg')" --output text
if ($rdsRule -ne 'True') {
    aws ec2 authorize-security-group-ingress --group-id $RdsSgId --protocol tcp --port 1433 --source-group $ecsSg | Out-Null
    Write-Host "SG: RDS now accepts 1433 from $EcsSgName"
} else { Write-Host "SG: RDS already accepts 1433 from $EcsSgName" }

# ---------- 3. IAM execution role (used by ECS itself, not by the app) ----------
$roleExists = aws iam list-roles --query "Roles[?RoleName=='$ExecRole'] | length(@)" --output text
if ($roleExists -eq '0') {
    $trust = @{
        Version = '2012-10-17'
        Statement = @(@{ Effect = 'Allow'; Principal = @{ Service = 'ecs-tasks.amazonaws.com' }; Action = 'sts:AssumeRole' })
    }
    aws iam create-role --role-name $ExecRole --assume-role-policy-document (ConvertTo-AwsJsonFile $trust) | Out-Null
    Write-Host "IAM: created $ExecRole"
} else { Write-Host "IAM: $ExecRole exists" }

# Pull from ECR + write to CloudWatch Logs
aws iam attach-role-policy --role-name $ExecRole `
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
# Read only the app's DB secret ("-*" matches the 6 random characters AWS appends to secret ARNs)
$secretPolicy = @{
    Version = '2012-10-17'
    Statement = @(@{
        Effect = 'Allow'; Action = 'secretsmanager:GetSecretValue'
        Resource = @(
            "arn:aws:secretsmanager:${Region}:${Account}:secret:$DbSecretName-*"
            "arn:aws:secretsmanager:${Region}:${Account}:secret:rds!db-*"
        )
    })
}
aws iam put-role-policy --role-name $ExecRole --policy-name read-english-db-secret `
    --policy-document (ConvertTo-AwsJsonFile $secretPolicy)

# ---------- 4. CloudWatch log groups ----------
foreach ($group in $Api.LogGroup, $Frontend.LogGroup, $DbInit.LogGroup) {
    $exists = aws logs describe-log-groups --log-group-name-prefix $group --query "logGroups[?logGroupName=='$group'] | length(@)" --output text
    if ($exists -eq '0') { aws logs create-log-group --log-group-name $group }
    aws logs put-retention-policy --log-group-name $group --retention-in-days 14
}
Write-Host 'Logs: log groups ready (14 days retention)'

# ---------- 5. ECS cluster ----------
aws ecs create-cluster --cluster-name $Cluster | Out-Null     # returns the existing cluster if already there
Write-Host "ECS: cluster $Cluster ready"

# ---------- 6. Load balancer, target groups, listener ----------
# create-load-balancer / create-listener return the existing one when called with the same settings
$albArn = aws elbv2 create-load-balancer --name $AlbName --type application --scheme internet-facing `
    --subnets @Subnets --security-groups $albSg --query 'LoadBalancers[0].LoadBalancerArn' --output text

$tgArn = @{}
foreach ($svc in $Api, $Frontend) {
    $health = @('--health-check-path', $svc.HealthPath, '--matcher', "HttpCode=$($svc.HealthCodes)",
                '--health-check-interval-seconds', '15', '--healthy-threshold-count', '2', '--unhealthy-threshold-count', '3')
    $existing = aws elbv2 describe-target-groups `
        --query "TargetGroups[?TargetGroupName=='$($svc.TargetGroup)'].TargetGroupArn | [0]" --output text
    if ($existing -eq 'None') {
        $tgArn[$svc.Service] = aws elbv2 create-target-group --name $svc.TargetGroup --protocol HTTP --port $svc.Port `
            --vpc-id $VpcId --target-type ip @health --query 'TargetGroups[0].TargetGroupArn' --output text
    } else {
        # Already there: apply the current health check settings from config.ps1
        $tgArn[$svc.Service] = $existing
        aws elbv2 modify-target-group --target-group-arn $existing @health | Out-Null
    }
    # Default is 300 s: every deploy would wait 5 minutes for old tasks to drain
    aws elbv2 modify-target-group-attributes --target-group-arn $tgArn[$svc.Service] `
        --attributes Key=deregistration_delay.timeout_seconds,Value=30 | Out-Null
}

# Port 80: everything goes to the frontend by default...
$listenerArn = aws elbv2 create-listener --load-balancer-arn $albArn --protocol HTTP --port 80 `
    --default-actions "Type=forward,TargetGroupArn=$($tgArn[$Frontend.Service])" `
    --query 'Listeners[0].ListenerArn' --output text

# ...except /api/*, which goes to the API
$apiRule = aws elbv2 describe-rules --listener-arn $listenerArn --query "Rules[?Priority=='10'] | length(@)" --output text
if ($apiRule -eq '0') {
    $conditions = @(@{ Field = 'path-pattern'; PathPatternConfig = @{ Values = @('/api/*') } })
    aws elbv2 create-rule --listener-arn $listenerArn --priority 10 --conditions (ConvertTo-AwsJsonFile $conditions) `
        --actions "Type=forward,TargetGroupArn=$($tgArn[$Api.Service])" | Out-Null
}
Write-Host 'ALB: listener :80 -> frontend, /api/* -> api'

Write-Host ''
Write-Host "Setup done. Load balancer: http://$(Get-AlbDnsName)"
Write-Host 'Next: ./deploy/ecs/deploy.ps1 -Tag <version>'
