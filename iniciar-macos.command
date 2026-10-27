#!/bin/bash
# O Terminal.app abre arquivos .command executáveis. Compatível com Bash 3.2.

set -u

# O Bash e o dirname do macOS bastam; não dependemos de readlink -f do GNU.
diretorio="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || exit 1
cd "$diretorio" || exit 1

esperar_saida() {
  local codigo="${1:-0}"
  printf '\nPressione Enter para fechar esta janela...'
  read -r _ || true
  exit "$codigo"
}

falhar() {
  printf '\n%s\n' "$1" >&2
  esperar_saida 1
}

command -v node >/dev/null 2>&1 || falhar 'Node.js 22 ou superior não foi encontrado. Instale-o e reabra o lançador.'
node_maior="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null)" || falhar 'Não foi possível identificar a versão do Node.js.'
[[ "$node_maior" =~ ^[0-9]+$ && "$node_maior" -ge 22 ]] || falhar "Este projeto precisa do Node.js 22 ou superior. Versão encontrada: $(node --version)"
command -v npm >/dev/null 2>&1 || falhar 'npm não foi encontrado. Instale-o junto com o Node.js.'

if [[ ! -d node_modules ]]; then
  printf 'Instalando dependências pela primeira vez...\n'
  npm install || falhar 'Não foi possível instalar as dependências.'
fi

# Sem túnel não há sala: o link público é o produto, então a falta do
# cloudflared para aqui, com o caminho de instalação, em vez de subir local.
command -v cloudflared >/dev/null 2>&1 || falhar 'cloudflared não foi encontrado. Instale com: brew install cloudflared'

# Este terminal fica aberto mostrando o link; o app de mesa abre ao lado.
# Ctrl+C aqui, ou fechar o app, derruba app, servidor e túnel juntos.
printf '\nIniciando o PeekIn...\n\n'
npm run iniciar
codigo=$?
# Encerrar de propósito (Ctrl+C sai com 130) não pede Enter; só um erro segura
# o terminal, para dar tempo de ler a mensagem.
[[ "$codigo" -eq 0 || "$codigo" -eq 130 ]] && exit 0
printf '\nNão foi possível iniciar.\n' >&2
esperar_saida "$codigo"
