@echo off
setlocal EnableExtensions DisableDelayedExpansion

if not defined MSYS2_ROOT set "MSYS2_ROOT=C:\msys64"
set "BASH=%MSYS2_ROOT%\usr\bin\bash.exe"
set "TOOLCHAIN=%MSYS2_ROOT%\ucrt64"
if not exist "%BASH%" goto missing_msys2
if not exist "%MSYS2_ROOT%\usr\bin\pacman.exe" goto missing_msys2
set "MSYSTEM=UCRT64"
set "CHERE_INVOKING=1"

if /i "%~1"=="check" goto check
if /i "%~1"=="update" goto update
if /i "%~1"=="setup" goto setup
if /i "%~1"=="build" goto build
if not "%~1"=="" goto usage
if not exist "%~dp0..\..\..\build\windows-ucrt64\RoboMasterClient2025.exe" goto build
goto launch

:check
echo MSYS2 found at "%MSYS2_ROOT%". Using UCRT64.
exit /b 0

:update
echo Updating MSYS2. If it asks to close MSYS2 processes, rerun update after it exits.
"%BASH%" --login -c "pacman -Syu && echo MSYS2 update command finished."
exit /b %errorlevel%

:setup
echo Installing the compiler, Qt and other build dependencies.
set "PACKAGES=mingw-w64-ucrt-x86_64-{gcc,cmake,ninja,pkgconf,qt6-base,qt6-declarative,qt6-multimedia,qt6-serialport,qt6-svg,abseil-cpp,protobuf,paho.mqtt.c,ffmpeg}"
"%BASH%" --login -c "pacman -S --needed %PACKAGES% && pacman -Q %PACKAGES% > /dev/null"
if errorlevel 1 exit /b 1
echo Build dependencies ready.
exit /b 0

:build
echo Building the SPR client.
if not exist "%TOOLCHAIN%\bin\cmake.exe" goto missing_deps
set "PATH=%TOOLCHAIN%\bin;%PATH%"
pushd "%~dp0..\..\.." || goto failed
cmake -S . -B build/windows-ucrt64 -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF ^
  -DCMAKE_C_COMPILER="%TOOLCHAIN%\bin\gcc.exe" -DCMAKE_CXX_COMPILER="%TOOLCHAIN%\bin\g++.exe" ^
  -DCMAKE_FIND_PACKAGE_PREFER_CONFIG=ON -DCMAKE_PREFIX_PATH="%TOOLCHAIN%" -DPAHO_MQTT_ROOT="%TOOLCHAIN%"
if errorlevel 1 goto failed_in_dir
cmake --build build/windows-ucrt64 --parallel 4
if errorlevel 1 goto failed_in_dir
popd

:launch
echo Opening the SPR client.
set "PATH=%TOOLCHAIN%\bin;%PATH%"
pushd "%~dp0..\..\..\build\windows-ucrt64" || goto failed
if not exist "RoboMasterClient2025.exe" goto failed_in_dir
start "" ".\RoboMasterClient2025.exe"
if errorlevel 1 goto failed_in_dir
popd
exit /b 0

:missing_msys2
echo MSYS2 not found at "%MSYS2_ROOT%".
echo This command ran before MSYS2 was installed or the script was given the wrong path.
echo Install MSYS2 from https://www.msys2.org/ then run: start-windows.bat check
echo For a custom installation directory, set MSYS2_ROOT in CMD and rerun check.
goto show_guide

:missing_deps
echo Build dependencies are missing. Run start-windows.bat setup in CMD, then repeat build.
goto show_guide

:usage
echo Usage: start-windows.bat [check^|update^|setup^|build]
exit /b 2

:failed_in_dir
popd
:failed
echo SPR client build or launch failed. See the error above.
:show_guide
echo Guide: "%~dp0..\..\..\docs\getting-started\user-guide.md"
if "%~1"=="" pause
exit /b 1
