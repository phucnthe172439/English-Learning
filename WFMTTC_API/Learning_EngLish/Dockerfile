# ---------- Stage 1: build ----------
# Image with the full .NET 10 SDK (compiler, dotnet CLI)
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copy only the project file first and restore NuGet packages.
# Docker caches this step, so packages are re-downloaded only when the .csproj changes.
COPY Learning_EngLish.csproj .
RUN dotnet restore

# Copy the rest of the source code and publish a Release build into /app
COPY . .
RUN dotnet publish -c Release -o /app --no-restore

# ---------- Stage 2: run ----------
# Smaller image with only the ASP.NET runtime (no SDK)
FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app .

# ASP.NET in containers listens on port 8080 by default
EXPOSE 8080

# Run as the image's built-in non-root user ("app"), not root.
# Works because 8080 is above 1024 and the app doesn't write files.
USER $APP_UID
ENTRYPOINT ["dotnet", "Learning_EngLish.dll"]
