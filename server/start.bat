@echo off
setlocal
cd /d "%~dp0"
echo 脚本所在目录: %CD%

echo Checking TypeScript...
call npx tsc --noEmit --excludeDirectories src/scripts
if errorlevel 1 (
    echo TypeScript check had warnings, but continuing anyway...
)

echo Starting server...
call npx tsx src/index.ts
