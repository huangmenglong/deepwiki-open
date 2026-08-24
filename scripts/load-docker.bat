@echo off
REM Load the image from a tar file on an intranet host (no internet required).
REM Usage: scripts\load-docker.bat [image.tar]
cd /d "%~dp0\.."

if "%~1"=="" (set TAR_FILE=deepwiki-open.tar) else (set TAR_FILE=%~1)
if not exist "%TAR_FILE%" (
  echo Image tar not found: %TAR_FILE%
  exit /b 1
)

echo Loading image from %TAR_FILE% ...
docker load -i %TAR_FILE%
echo Done. Now copy .env.example to .env, fill in your internal AI/embed
echo endpoints, then run deploy.bat.
