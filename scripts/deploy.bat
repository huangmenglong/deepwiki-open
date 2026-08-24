@echo off
REM Start DeepWiki via docker compose.
REM Requires .env (copy from .env.example and fill in internal AI/embed endpoints).
cd /d "%~dp0\.."

if not exist .env (
  echo No .env found. Copying .env.example ^-^> .env ...
  copy .env.example .env >nul
  echo Please edit .env and set OPENAI_BASE_URL / DEEPWIKI_EMBED_MODEL /
  echo DEEPWIKI_DEFAULT_MODEL etc., then re-run this script.
  exit /b 1
)

docker image inspect deepwiki-open:latest >nul 2>&1
if errorlevel 1 (
  echo Warning: image deepwiki-open:latest is not present locally.
  echo On an intranet host, load it first:  scripts\load-docker.bat deepwiki-open.tar
)

echo Starting DeepWiki with docker compose ...
docker compose up -d

if "%PORT%"=="" set PORT=8001
echo DeepWiki is starting.
echo   Web UI: http://localhost:3000/
echo   API:    http://localhost:%PORT%/
echo   Logs:   docker compose logs -f deepwiki
