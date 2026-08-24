@echo off
REM Save the built image to a tar file so it can be copied onto an intranet host.
cd /d "%~dp0\.."

if "%IMAGE_NAME%"=="" set IMAGE_NAME=deepwiki-open:latest
if "%OUT_FILE%"=="" set OUT_FILE=deepwiki-open.tar

echo Saving %IMAGE_NAME% ^-^> %OUT_FILE% ...
docker save -o %OUT_FILE% %IMAGE_NAME%
echo Done. Transfer %OUT_FILE% to the intranet host, then run load-docker.bat there.
