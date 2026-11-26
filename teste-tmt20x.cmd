@echo off
rem Duplo clique para rodar o teste. Le o .ps1 como texto e executa como scriptblock,
rem do mesmo jeito do ssh-tunel: nao depende da ExecutionPolicy da maquina.
powershell -NoProfile -Command "& ([scriptblock]::Create((Get-Content -Raw -LiteralPath '%~dp0teste-tmt20x.ps1')))"
pause
