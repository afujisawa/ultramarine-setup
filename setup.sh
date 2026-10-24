#!/usr/bin/env bash
set -euo pipefail

# Parâmetros
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


