@echo off
title DayZ Solo - Loot Editor
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0DayZSolo.ps1" -ShowMissionFolder
start "" "%~dp0tools\loot-editor.html"
pause
