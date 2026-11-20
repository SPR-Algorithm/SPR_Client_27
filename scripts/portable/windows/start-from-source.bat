@echo off
setlocal EnableExtensions DisableDelayedExpansion

if not defined MSYS2_ROOT set "MSYS2_ROOT=C:\msys64"
set "BASH=%MSYS2_ROOT%\usr\bin\bash.exe"
set "TOOLCHAIN=%MSYS2_ROOT%\mingw64"
if not exist "%BASH%" goto missing_msys2
set "MSYSTEM=MINGW64"
set "CHERE_INVOKING=1"

if /i "%~1"=="update" goto update
if /i "%~1"=="setup" goto setup
if /i "%~1"=="build" goto build
if not "%~1"=="" goto usage
if not exist "%~dp0..\..\..\build\windows\RoboMasterClient2025.exe" goto build
goto launch

:update
"%BASH%" --login -c "pacman -Syu"
exit /b %errorlevel%

:setup
"%BASH%" --login -c "pacman -S --needed mingw-w64-x86_64-{gcc,cmake,ninja,pkgconf,qt6-base,qt6-declarative,qt6-multimedia,qt6-serialport,qt6-svg,abseil-cpp,protobuf,paho.mqtt.c,ffmpeg}"
exit /b %errorlevel%

:build
if not exist "%TOOLCHAIN%\bin\cmake.exe" goto missing_deps
set "PATH=%TOOLCHAIN%\bin;%PATH%"
pushd "%~dp0..\..\.." || goto failed
cmake -S . -B build/windows -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF ^
  -DCMAKE_C_COMPILER="%TOOLCHAIN%\bin\gcc.exe" -DCMAKE_CXX_COMPILER="%TOOLCHAIN%\bin\g++.exe" ^
  -DCMAKE_FIND_PACKAGE_PREFER_CONFIG=ON -DCMAKE_PREFIX_PATH="%TOOLCHAIN%" -DPAHO_MQTT_ROOT="%TOOLCHAIN%"
if errorlevel 1 goto failed_in_dir
cmake --build build/windows --parallel 4
if errorlevel 1 goto failed_in_dir
popd

:launch
set "PATH=%TOOLCHAIN%\bin;%PATH%"
pushd "%~dp0..\..\..\build\windows" || goto failed
start "" "RoboMasterClient2025.exe"
if errorlevel 1 goto failed_in_dir
popd
exit /b 0

:missing_msys2
echo MSYS2 was not found at "%MSYS2_ROOT%".
echo Install MSYS2 from https://www.msys2.org/ or set MSYS2_ROOT to its install directory.
goto show_guide

:missing_deps
echo Build dependencies are missing. Run this script with update, then setup, from CMD.
goto show_guide

:usage
echo Usage: start-from-source.bat [update^|setup^|build]
exit /b 2

:failed_in_dir
popd
:failed
echo SPR client build or launch failed. See the error above.
:show_guide
echo Guide: docs\getting-started\user-guide.md
pause
exit /b 1
