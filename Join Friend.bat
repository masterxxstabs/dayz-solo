@echo off
title DayZ Solo - Join a friend
echo Paste the invite code your friend sent you (right-click pastes), then press Enter.
set CODE=
set /p CODE=Invite code: 
if not defined CODE (
  echo No code entered.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0DayZSolo.ps1" -Invite "%CODE%"
if errorlevel 1 pause
