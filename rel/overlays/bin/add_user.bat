@echo off
setlocal enabledelayedexpansion

if "%~1"=="" (
  echo Usage: %0 ^<email^> ^<password^>
  exit /b 1
)
if "%~2"=="" (
  echo Usage: %0 ^<email^> ^<password^>
  exit /b 1
)

cd /d "%~dp0"
.\nexus eval "Nexus.Release.add_user(\"!~1\", \"!~2\")"
