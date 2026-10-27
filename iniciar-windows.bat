@echo off
setlocal
set "CODIGO_SAIDA=0"
title PeekIn
cd /d "%~dp0"

where node >nul 2>nul
if errorlevel 1 (
  echo Node.js 22 ou superior nao foi encontrado.
  echo Instale com: winget install OpenJS.NodeJS.LTS
  goto erro
)

set "NODE_MAIOR="
for /f "tokens=1 delims=." %%V in ('node -p "process.versions.node"') do set "NODE_MAIOR=%%V"
if not defined NODE_MAIOR (
  echo Nao foi possivel identificar a versao do Node.js.
  goto erro
)
if %NODE_MAIOR% LSS 22 (
  echo Este projeto precisa do Node.js 22 ou superior. Versao encontrada:
  node --version
  goto erro
)

where npm >nul 2>nul
if errorlevel 1 (
  echo npm nao foi encontrado. Instale-o junto com o Node.js.
  goto erro
)

if not exist node_modules (
  echo Instalando dependencias pela primeira vez...
  call npm install
  if errorlevel 1 goto falhou
)

rem Sem tunel nao ha sala: o link publico e o produto, entao a falta do
rem cloudflared para aqui, com o caminho de instalacao, em vez de subir local.
where cloudflared >nul 2>nul
if errorlevel 1 (
  echo cloudflared nao foi encontrado.
  echo Instale com: winget install --id Cloudflare.cloudflared
  goto erro
)

rem Esta janela fica aberta mostrando o link; o app de mesa abre ao lado.
rem Ctrl+C aqui, ou fechar o app, derruba app, servidor e tunel juntos.
echo.
echo Iniciando o PeekIn...
echo.
call npm run iniciar
if errorlevel 1 goto falhou
exit /b 0

:falhou
echo.
echo Nao foi possivel iniciar.

:erro
set "CODIGO_SAIDA=1"
echo.
pause
exit /b %CODIGO_SAIDA%
