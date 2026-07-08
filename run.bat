@echo off
rem Launch Sleepover from your own user session so Steam IPC works.
start "" "%USERPROFILE%\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe" --path "%~dp0."
