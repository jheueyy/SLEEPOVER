@echo off
setlocal enabledelayedexpansion
rem Launch Sleepover from your own user session so Steam IPC works.
rem
rem Godot ships as a single portable .exe, so everyone unzips it somewhere
rem different -- hardcoding one path broke this on the first playtester's
rem machine. Look in the usual places, then search, then fall back to PATH.

rem 0. Explicit override always wins:  set GODOT=C:\path\to\godot.exe  &  run.bat
if defined GODOT if exist "%GODOT%" goto :run
set "GODOT="

rem 1. Common unzip layouts (a file -- not the same-named folder the zip creates).
for %%D in (
  "%USERPROFILE%\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe"
  "%USERPROFILE%\Downloads\Godot_v4.7-stable_win64\Godot_v4.7-stable_win64.exe"
  "%USERPROFILE%\Downloads\Godot_v4.7-stable_win64.exe"
  "%USERPROFILE%\Desktop\Godot_v4.7-stable_win64.exe"
  "%LOCALAPPDATA%\Programs\Godot\Godot_v4.7-stable_win64.exe"
  "%ProgramFiles%\Godot\Godot_v4.7-stable_win64.exe"
) do (
  if not defined GODOT if exist %%D if not exist "%%~D\" set "GODOT=%%~D"
)

rem 2. Anything Godot-shaped under Downloads or Desktop, however it was unzipped.
if not defined GODOT (
  for /f "delims=" %%P in ('dir /b /s "%USERPROFILE%\Downloads\Godot*win64*.exe" 2^>nul') do (
    if not defined GODOT set "GODOT=%%P"
  )
)
if not defined GODOT (
  for /f "delims=" %%P in ('dir /b /s "%USERPROFILE%\Desktop\Godot*win64*.exe" 2^>nul') do (
    if not defined GODOT set "GODOT=%%P"
  )
)

rem 3. On PATH.
if not defined GODOT (
  for /f "delims=" %%P in ('where godot 2^>nul') do if not defined GODOT set "GODOT=%%P"
)

if not defined GODOT (
  echo.
  echo   Could not find Godot 4.7 on this machine.
  echo.
  echo   Either put Godot_v4.7-stable_win64.exe in your Downloads folder,
  echo   or point this script straight at it:
  echo.
  echo       set GODOT=C:\wherever\Godot_v4.7-stable_win64.exe
  echo       run.bat
  echo.
  echo   Download: https://godotengine.org/download/windows/
  echo   ^(standard build, NOT the .NET one^)
  echo.
  pause
  exit /b 1
)

:run
echo Launching: %GODOT%
start "" "%GODOT%" --path "%~dp0."
