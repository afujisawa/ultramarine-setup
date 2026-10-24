#!/usr/bin/env bash
set -euo pipefail

# Parâmetros
OS_RELEASE=/etc/os-release

USUARIO_REAL="${SUDO_USER:-$USER}"
HOME_REAL="$(getent passwd "$USUARIO_REAL" | cut -d: -f6)"
USER_UID=$(id -u "$USUARIO_REAL")
DBUS_ADDRESS="unix:path=/run/user/$USER_UID/bus"

PACOTES_REMOVER=(gnome-maps "libreoffice-*")
PACOTES_DNF="ShellCheck shfmt zed vlc gtk-murrine-engine sassc bibata-cursor-theme papirus-icon-theme-dark gnome-tweaks"
PACOTES_FLATPAK=("")

TOTAL_SUCESSO=0
TOTAL_ERRO=0

#Cores
AZUL=$'\e[1;34m'
VERDE=$'\e[1;32m'
AMARELO=$'\e[1;33m'
VERMELHO=$'\e[1;31m'
RESETAR=$'\e[0m'

# Funções
mensagem() {
	case "$1" in
		"INFO") COR="$AZUL" ;;
		"SUCESSO") COR="$VERDE" TOTAL_SUCESSO=$((TOTAL_SUCESSO + 1)) ;;
		"ALERTA") COR="$AMARELO" TOTAL_SUCESSO=$((TOTAL_SUCESSO + 1)) ;;
		"ERRO") COR="$VERMELHO" TOTAL_ERRO=$((TOTAL_ERRO + 1)) ;;
		*)
			printf "%s[ERRO] Mensagem não identificada\n" "$VERMELHO"
			exit 1
			;;
	esac

	printf "%s[%s]%s %s\n" "$COR" "$1" "$RESETAR" "$2."
}

verifica_permissao() {
	if [ "$EUID" -eq 0 ]; then
		mensagem "SUCESSO" "Permissão root confirmada"
	else
		mensagem "ERRO" "Execute com o comando sudo"
		exit 1
	fi
}

verifica_distro() {
	if [[ -f "$OS_RELEASE" ]]; then
		# shellcheck disable=SC1090
		source "$OS_RELEASE"

		if [[ "$ID" == "ultramarine" ]]; then
			mensagem "SUCESSO" "Distribuição Ultramarine detectada"
		else
			mensagem "ERRO" "Script exclusivo para distribuição Ultramarine"
			exit 1
		fi
	else
		mensagem "ERRO" "Não foi possível identificar a distribuição"
		mensagem "INFO" "Arquivo $OS_RELEASE não encontrado"
		exit 1
	fi
}

verifica_internet() {
	if ping -c 1 8.8.8.8 &>/dev/null; then
		mensagem "SUCESSO" "Conexão com a internet ativa"
	else
		mensagem "ERRO" "Sem acesso à internet"
		exit 1
	fi
}

remover_programas() {
	mensagem "INFO" "Removendo programas não utilizados"
	if dnf remove -y "$PACOTES_REMOVER" &>/dev/null; then
		mensagem "SUCESSO" "Aplicativos removidos com sucesso"
	else
		mensagem "ERRO" "Falha ao remover os pacotes"
		exit 1
	fi

	if dnf autoremove -y &>/dev/null; then
		mensagem "SUCESSO" "Limpeza de dependências concluída"
	else
		mensagem "ERRO" "Falha ao executar o autoremove"
		exit 1
	fi
}

atualizar_sistema() {
	mensagem "INFO" "Atualizando pacotes do sistema"
	if dnf upgrade -y --refresh &>/dev/null; then
		mensagem "SUCESSO" "Sistema atualizado com sucesso"
	else
		mensagem "ERRO" "Falha ao atualizar o sistema"
		exit 1
	fi
}

instalar_pacote() {
	local gerenciador=$1
	local pacote=$2

	case $gerenciador in
		"dnf")
			if rpm -q "$pacote" &>/dev/null; then
				mensagem "ALERTA" "Pacote DNF '$pacote' já está instalado"
			else
				mensagem "INFO" "Instalando pacote DNF: $pacote"
				if dnf install -y "$pacote" &>/dev/null; then
					mensagem "SUCESSO" "Pacote '$pacote' instalado com sucesso"
				else
					mensagem "ERRO" "Falha ao instalar o pacote DNF '$pacote'"
					return 1
				fi
			fi
			;;
		"flatpak")
			if flatpak list --app --columns=application | grep -q "^$pacote$"; then
				mensagem "ALERTA" "Aplicativo Flatpak '$pacote' já está instalado"
			else
				mensagem "INFO" "Instalando Flatpak: $pacote"
				if flatpak install -y flathub "$pacote" &>/dev/null; then
					mensagem "SUCESSO" "Flatpak '$pacote' instalado com sucesso"
				else
					mensagem "ERRO" "Falha ao instalar o Flatpak '$pacote'"
					return 1
				fi
			fi
			;;
		*)
			mensagem "ERRO" "Gerenciador de pacotes desconhecido: $gerenciador"
			return 1
			;;
	esac
}

instalar_lote() {
	mensagem "INFO" "Iniciando instalação de pacotes (DNF)"
	for pacote in $PACOTES_DNF; do
		instalar_pacote "dnf" "$pacote"
	done

	mensagem "INFO" "Iniciando instalação de aplicativos (Flatpak)"
	for app in $PACOTES_FLATPAK; do
		instalar_pacote "flatpak" "$app"
	done
}

instalar_via_git() {
	local nome="$1"
	local url="$2"
	local destino="$3"
	local instalar="${4:-}"

	if [ -d "$destino" ]; then
		mensagem "ALERTA" "$nome já está instalado para o usuário $USUARIO_REAL"
		return 0
	fi

	mensagem "INFO" "Clonando $nome"
	if sudo -u "$USUARIO_REAL" env HOME="$HOME_REAL" git clone "$url" "$destino" &>/dev/null; then
		mensagem "SUCESSO" "Repositório $nome clonado"
		if [[ -n "$instalar" ]]; then
			mensagem "INFO" "Instalando $nome"
			if sudo -u "$USUARIO_REAL" env HOME="$HOME_REAL" bash -c "$destino/$instalar &>/dev/null"; then
				mensagem "SUCESSO" "$nome instalado"
			else
				mensagem "ERRO" "Falha ao instalar $nome"
				return 1
			fi
		fi
	else
		mensagem "ERRO" "Falha ao clonar ou instalar o $nome"
		return 1
	fi
}

executar(){
	local nome=$1
	local comando=$2

	if [ ! -S "/run/user/$USER_UID/bus" ]; then
	DBUS_ADDRESS=$(pgrep -u "$USER_UID" -a gnome-session | grep -o 'DBUS_SESSION_BUS_ADDRESS=[^ ]*' | cut -d= -f2-)
	fi

	if sudo -u "$USUARIO_REAL" env HOME="$HOME_REAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDRESS" bash -c "$comando"; then
		mensagem "SUCESSO" "$nome concluído"
	else
		mensagem "ERRO" "Comando $comando falhou"
		return 1
	fi
}

exibir_resumo() {
	local status_final=0

	echo ""
	echo "=========================================="
	echo "		  RESUMO DA EXECUÇÃO			  "
	echo "=========================================="
	mensagem "SUCESSO" "Ações bem-sucedidas: $TOTAL_SUCESSO"
	if [ "$TOTAL_ERRO" -gt 0 ]; then
		mensagem "ERRO" "Erros encontrados: $TOTAL_ERRO"
		status_final=1
	else
		mensagem "SUCESSO" "Erros encontrados: $TOTAL_ERRO"
		status_final=0
	fi

	echo "=========================================="
	return "$status_final"
}

# Execução
clear
verifica_permissao
verifica_distro
verifica_internet
remover_programas
atualizar_sistema
instalar_lote

instalar_via_git "Tmux Plugin Manager (TPM)" \
	"https://github.com/tmux-plugins/tpm" \
	"$HOME_REAL/.tmux/plugins/tpm"

instalar_via_git "Tokyonight-GTK-Theme" \
	"https://github.com/Fausto-Korpsvart/Tokyonight-GTK-Theme.git" \
	"$HOME_REAL/Downloads/Tokyonight-GTK-Theme"\
	"themes/./install.sh --tweaks storm macos -t red -l"

executar "Alterar tema do mouse" \
	"gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Ice'"

executar "Alterar tema de icones" \
	"gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'"

executar "Alterar tema das aplicações legadas" \
	"gsettings set org.gnome.desktop.interface gtk-theme 'Tokyonight-Red-Dark-Storm'"

executar "Alterar papel de parede" \
	"gsettings set org.gnome.desktop.background picture-uri-dark $HOME_REAL/Pictures/samurai-warrior-night-by-lake.jpg"

executar "Ativa extensão Pop-Shell" \
	"gnome-extensions enable pop-shell@system76.com"

exibir_resumo
