# Shared names and IDs for setup.ps1 and deploy.ps1. Change values here, not in the scripts.
# Dot-sourced by both scripts: . "$PSScriptRoot/config.ps1"

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true    # a failing aws/docker command stops the script

$Region = 'ap-southeast-1'
$env:AWS_DEFAULT_REGION = $Region
$Account  = aws sts get-caller-identity --query Account --output text
$Registry = "$Account.dkr.ecr.$Region.amazonaws.com"

# Existing network and database (created for the EC2 setup, docs/07-aws-ec2-rds.md)
$VpcId   = 'vpc-00ee05cab5f80c6f2'                  # default VPC, same as RDS database-1
$Subnets = @(                                       # public subnets: tasks get a public IP to pull images from ECR (no NAT gateway needed)
    'subnet-0471457d756818ccc'                      # ap-southeast-1a
    'subnet-0b7978c1d3eb28183'                      # ap-southeast-1b
    'subnet-0363ff12f2a6e2049'                      # ap-southeast-1c
)
$RdsInstance  = 'database-1'                        # RDS for SQL Server; its admin password is in a "rds!db-..." secret
$RdsSgId      = 'sg-03c4e8ce7f0796dd9'              # english-rds-sg on database-1
$DbSecretName = 'english-learning/prod/db'          # host, port, dbname, username, password of the english_app login

# New ECS resources
$Cluster   = 'english-learning'
$AlbName   = 'english-alb'
$AlbSgName = 'english-alb-sg'                       # internet -> ALB :80
$EcsSgName = 'english-ecs-sg'                       # ALB -> tasks; tasks -> RDS :1433
$ExecRole  = 'english-ecs-execution-role'           # lets ECS pull from ECR, write logs, read the DB secret

$Api = @{
    Service = 'english-api'; Container = 'api'; Repo = 'english-api'; Port = 8080
    TargetGroup = 'english-api-tg'; HealthPath = '/health'; HealthCodes = '200'
    LogGroup = '/ecs/english-api'; BuildContext = 'WFMTTC_API/Learning_EngLish'
}
$Frontend = @{
    Service = 'english-frontend'; Container = 'frontend'; Repo = 'english-frontend'; Port = 4000
    TargetGroup = 'english-frontend-tg'; HealthPath = '/healthz'; HealthCodes = '200'   # /healthz: see src/server.ts
    LogGroup = '/ecs/english-frontend'; BuildContext = 'FrontEnd/English_FrontEnd'
}
# One-off task that runs database/init-db.sh against RDS (init-db.ps1), not a service
$DbInit = @{
    Family = 'english-db-init'; Container = 'db-init'; Repo = 'english-db-init'
    LogGroup = '/ecs/english-db-init'; BuildContext = 'database'
}

# Writes an object as JSON to a temp file and returns "file://..." for the aws CLI
# (avoids PowerShell quoting problems with inline JSON).
# -InputObject (not the pipeline) so a one-item array stays a JSON array.
function ConvertTo-AwsJsonFile($InputObject) {
    $file = New-TemporaryFile
    ConvertTo-Json -InputObject $InputObject -Depth 20 | Set-Content -Path $file -Encoding utf8NoBOM
    "file://$($file.FullName)"
}

function Get-SecurityGroupId([string] $Name) {
    aws ec2 describe-security-groups --filters "Name=group-name,Values=$Name" "Name=vpc-id,Values=$VpcId" `
        --query 'SecurityGroups[0].GroupId' --output text
}

function Get-AlbDnsName {
    aws elbv2 describe-load-balancers --query "LoadBalancers[?LoadBalancerName=='$AlbName'].DNSName | [0]" --output text
}
