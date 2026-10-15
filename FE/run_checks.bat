@echo off
setlocal EnableExtensions
chcp 65001 >nul
set "ROOT=%~dp0"
set "LOGS=%~dp0_logs"
if not exist "%LOGS%" mkdir "%LOGS%"
if exist "%LOGS%\DONE.txt" del /q "%LOGS%\DONE.txt"

echo [env] flutter / node versions
where flutter > "%LOGS%\00_env.log" 2>&1
call flutter --version >> "%LOGS%\00_env.log" 2>&1
where node >> "%LOGS%\00_env.log" 2>&1
call node -v >> "%LOGS%\00_env.log" 2>&1
call npm -v >> "%LOGS%\00_env.log" 2>&1

rem ================= MOBILE =================
cd /d "%ROOT%Mobile"
if exist "android\" goto skipcreate
echo [mobile] flutter create (android, ios)
call flutter create --org vn.veganlife --project-name veganlife_mobile --platforms android,ios . > "%LOGS%\01_flutter_create.log" 2>&1
>> "%LOGS%\01_flutter_create.log" echo EXIT=%ERRORLEVEL%
:skipcreate

echo [mobile] flutter pub get
call flutter pub get > "%LOGS%\02_pub_get.log" 2>&1
>> "%LOGS%\02_pub_get.log" echo EXIT=%ERRORLEVEL%

echo [mobile] dart format
call dart format lib test > "%LOGS%\02b_format.log" 2>&1
>> "%LOGS%\02b_format.log" echo EXIT=%ERRORLEVEL%

echo [mobile] flutter analyze
call flutter analyze > "%LOGS%\03_analyze.log" 2>&1
>> "%LOGS%\03_analyze.log" echo EXIT=%ERRORLEVEL%

echo [mobile] flutter test
call flutter test --reporter expanded > "%LOGS%\04_test.log" 2>&1
>> "%LOGS%\04_test.log" echo EXIT=%ERRORLEVEL%

rem ================= WEB =================
cd /d "%ROOT%Web"
if not exist ".env.local" copy /y ".env.example" ".env.local" >nul

echo [web] npm install
call npm install --no-audit --no-fund > "%LOGS%\11_npm_install.log" 2>&1
>> "%LOGS%\11_npm_install.log" echo EXIT=%ERRORLEVEL%

echo [web] tsc --noEmit
call npx tsc --noEmit > "%LOGS%\12_tsc.log" 2>&1
>> "%LOGS%\12_tsc.log" echo EXIT=%ERRORLEVEL%

echo [web] eslint
call npm run lint > "%LOGS%\13_lint.log" 2>&1
>> "%LOGS%\13_lint.log" echo EXIT=%ERRORLEVEL%

echo [web] next build
call npm run build > "%LOGS%\14_build.log" 2>&1
>> "%LOGS%\14_build.log" echo EXIT=%ERRORLEVEL%

> "%LOGS%\DONE.txt" echo DONE
echo.
echo Xong. Log nam trong FE\_logs
pause
