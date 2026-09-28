@echo off
:: First-time setup on a new machine.
::
::   1. Clone devboard-infra into an empty folder (e.g. C:\DevBoard).
::   2. Run this from inside it.
::
:: It clones every other repo next to it, writes every .env with matching
:: secrets, and starts the stack. Safe to re-run: it never overwrites a value
:: you have already set. The work is in bootstrap.ps1.
::
:: Pass -NoStart to clone and configure without starting anything.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bootstrap.ps1" %*
exit /b %ERRORLEVEL%
