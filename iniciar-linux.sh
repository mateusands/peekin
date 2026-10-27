#!/usr/bin/env bash
# Lançador Linux; a execução de scripts pelo gerenciador de arquivos depende dele.

set -u

arquivo_script="$(readlink -f -- "${BASH_SOURCE[0]}")"

# Atalho no menu de aplicativos: bash iniciar-linux.sh --instalar-atalho
# (ou --remover-atalho). O .desktop é gerado aqui, e não versionado, porque
# Exec e Icon exigem caminho absoluto, que muda de máquina para máquina.
case "${1:-}" in
  --instalar-atalho|--remover-atalho)
    raiz="$(dirname -- "$arquivo_script")"
    destino="${XDG_DATA_HOME:-$HOME/.local/share}/applications/peekin.desktop"
    if [[ "$1" == --remover-atalho ]]; then
      rm -f "$destino"
      printf 'Atalho removido.\n'
    else
      mkdir -p "$(dirname -- "$destino")"
      # Terminal=false: o próprio script abre o terminal onde a sala roda
      cat > "$destino" <<DESKTOP
[Desktop Entry]
Type=Application
Name=PeekIn
Comment=Chamada P2P de compartilhamento de tela, com ou sem som
Exec="$arquivo_script"
Icon=$raiz/assets/peekin-icon.png
Path=$raiz
Terminal=false
Categories=Network;VideoConference;
DESKTOP
      chmod +x "$destino"
      command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$(dirname -- "$destino")" 2>/dev/null
      printf 'Atalho criado: %s\n' "$destino"
    fi
    exit 0
    ;;
esac

# Executado pelo gerenciador de arquivos, o script normalmente não recebe um
# terminal. A alternativa Debian tem preferência; nas outras distribuições
# procuramos um emulador instalado. A variável evita abrir uma segunda janela.
if [[ ! -t 0 && "${PEEKIN_EM_TERMINAL:-}" != '1' ]]; then
  for terminal in x-terminal-emulator "${TERMINAL:-}" konsole gnome-terminal xfce4-terminal alacritty kitty foot xterm; do
    [[ -n "$terminal" ]] && command -v "$terminal" >/dev/null 2>&1 || continue
    # GNOME e Xfce precisam de delimitadores próprios para preservar os argumentos.
    case "${terminal##*/}" in
      gnome-terminal) separador='--' ;;
      xfce4-terminal) separador='--execute' ;;
      *) separador='-e' ;;
    esac
    exec "$terminal" "$separador" env PEEKIN_EM_TERMINAL=1 "$arquivo_script"
  done
  mensagem='Não encontrei um terminal para abrir o PeekIn. Instale um terminal ou execute bash iniciar-linux.sh em um terminal existente.'
  printf '%s\n' "$mensagem" >&2
  # Sem terminal, stderr fica invisível ao abrir pelo gerenciador de arquivos.
  if command -v zenity >/dev/null 2>&1; then
    zenity --error --text="$mensagem"
  elif command -v kdialog >/dev/null 2>&1; then
    kdialog --error "$mensagem"
  fi
  exit 1
fi

diretorio="$(dirname -- "$arquivo_script")"
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

command -v node >/dev/null 2>&1 || falhar 'Node.js 22 ou superior não foi encontrado.'
node_maior="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null)" || falhar 'Não foi possível identificar a versão do Node.js.'
[[ "$node_maior" =~ ^[0-9]+$ && "$node_maior" -ge 22 ]] || falhar "Este projeto precisa do Node.js 22 ou superior. Versão encontrada: $(node --version)"

command -v npm >/dev/null 2>&1 || falhar 'npm não foi encontrado. Instale-o junto com o Node.js.'
if [[ ! -d node_modules ]]; then
  printf 'Instalando dependências pela primeira vez...\n'
  npm install || falhar 'Não foi possível instalar as dependências.'
fi

# Sem túnel não há sala: o link público é o produto, então a falta do
# cloudflared para aqui, com o caminho de instalação, em vez de subir local.
command -v cloudflared >/dev/null 2>&1 || falhar 'cloudflared não foi encontrado. Instale com: sudo pacman -S cloudflared (Arch/CachyOS), ou o .deb de github.com/cloudflare/cloudflared/releases (Debian/Ubuntu).'

# Este terminal fica aberto mostrando o link; o app de mesa abre ao lado.
# Ctrl+C aqui, ou fechar o app, derruba app, servidor e túnel juntos.
printf '\nIniciando o PeekIn...\n\n'
npm run iniciar
codigo=$?
# Encerrar de propósito (Ctrl+C sai com 130) fecha a janela na hora; só um
# erro segura o terminal, para dar tempo de ler a mensagem.
[[ "$codigo" -eq 0 || "$codigo" -eq 130 ]] && exit 0
printf '\nNão foi possível iniciar.\n' >&2
esperar_saida "$codigo"
