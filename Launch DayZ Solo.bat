@echo off
title DayZ Solo
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0DayZSolo.ps1" %*
if errorlevel 1 pause
