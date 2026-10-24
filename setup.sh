#!/usr/bin/env bash
set -euo pipefail

# Parâmetros
OS_RELEASE=/etc/os-release

PACOTES_REMOVER=(gnome-maps "libreoffice-*")
PACOTES_DNF="ShellCheck shfmt zed vlc"
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


# Execução
clear
verifica_permissao
verifica_distro
verifica_internet
remover_programas
atualizar_sistema
instalar_lote
