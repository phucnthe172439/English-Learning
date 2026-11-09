# One-shot image that creates or repairs the database on AWS RDS.
# Run as an ECS task by deploy/ecs/init-db.ps1. Same image (for its sqlcmd) and same script
# as the db-init service in docker-compose.yml, which mounts this folder instead of using this image.
FROM mcr.microsoft.com/mssql/server:2025-latest
COPY 01-schema.sql 02-seed.sql 03-app-login.sql init-db.sh /scripts/
ENTRYPOINT ["/bin/bash", "/scripts/init-db.sh"]
