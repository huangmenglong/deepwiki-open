@echo off
REM Build the DeepWiki Docker image.
REM NOTE: building requires network access (npm ci + poetry install + base
REM images). Build once on an internet-connected machine, then use save-docker.bat
REM to transfer the image to your intranet hosts.
REM
REM Intranet/corporate overrides (all optional, set as env vars before running):
REM   NPM_REGISTRY=...         npm registry, e.g. https://registry.npmmirror.com
REM   HTTP_PROXY / HTTPS_PROXY corporate proxy used by npm/pip during the build
REM   APT_MIRROR=...           Debian apt mirror, e.g. http://10.0.0.1/debian
REM   APT_SECURITY_MIRROR=...  Debian security mirror
REM   PIP_TRUSTED_HOST=...     pip trusted host for a plain-http mirror
cd /d "%~dp0\.."

if "%IMAGE_NAME%"=="" set IMAGE_NAME=deepwiki-open:latest

set ARGS=
if not "%NPM_REGISTRY%"=="" set ARGS=%ARGS% --build-arg NPM_REGISTRY=%NPM_REGISTRY%
if not "%HTTP_PROXY%"=="" set ARGS=%ARGS% --build-arg HTTP_PROXY=%HTTP_PROXY%
if not "%HTTPS_PROXY%"=="" set ARGS=%ARGS% --build-arg HTTPS_PROXY=%HTTPS_PROXY%
if not "%NO_PROXY%"=="" set ARGS=%ARGS% --build-arg NO_PROXY=%NO_PROXY%
if not "%APT_MIRROR%"=="" set ARGS=%ARGS% --build-arg APT_MIRROR=%APT_MIRROR%
if not "%APT_SECURITY_MIRROR%"=="" set ARGS=%ARGS% --build-arg APT_SECURITY_MIRROR=%APT_SECURITY_MIRROR%
if not "%PIP_TRUSTED_HOST%"=="" set ARGS=%ARGS% --build-arg PIP_TRUSTED_HOST=%PIP_TRUSTED_HOST%

echo Building image %IMAGE_NAME% ...
docker build %ARGS% -t %IMAGE_NAME% .
echo Done: %IMAGE_NAME%
