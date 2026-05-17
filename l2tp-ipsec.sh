#!/bin/bash
#
# L2TP/IPSec — меню установки и управления
# Версия 1.0
#

set -o pipefail
umask 077

readonly SCRIPT_VERSION="1.0"

# ─── Цвета и оформление ────────────────────────────────────────────────────
if [[ -t 1 ]]; then
	RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
	BLUE=$'\033[0;34m'; MAGENTA=$'\033[0;35m'; CYAN=$'\033[0;36m'
	WHITE=$'\033[1;37m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'
	C_AQUA=$'\033[38;5;45m'; C_TEAL=$'\033[38;5;79m'
	C_LIME=$'\033[38;5;120m'; C_PINK=$'\033[38;5;213m'
	C_ORANGE=$'\033[38;5;214m'; C_GREY=$'\033[38;5;245m'
	C_VIOLET=$'\033[38;5;141m'; C_GOLD=$'\033[38;5;220m'
	C_STEEL=$'\033[38;5;75m'
else
	RED=''; GREEN=''; YELLOW=''; BLUE=''; MAGENTA=''; CYAN=''
	WHITE=''; BOLD=''; DIM=''; NC=''
	C_AQUA=''; C_TEAL=''; C_LIME=''; C_PINK=''; C_ORANGE=''; C_GREY=''
	C_VIOLET=''; C_GOLD=''; C_STEEL=''
fi

msg()  { printf '%s\n' "$*"; }
info() { printf '%b\n' "  ${C_AQUA}ℹ${NC}  $*"; }
ok()   { printf '%b\n' "  ${GREEN}✔${NC}  $*"; }
warn() { printf '%b\n' "  ${YELLOW}⚠${NC}  $*"; }
err()  { printf '%b\n' "  ${RED}✖${NC}  $*" >&2; }
hint() { printf '%b\n' "     ${DIM}↳ $*${NC}"; }
step() { printf '\n  %b━━━ %s ━━━%b\n' "$C_VIOLET" "$*" "$NC"; }

# Длина строки в символах (UTF-8), без ANSI
strlen_visual() {
	local s="$1"
	s=$(printf '%s' "$s" | sed -E $'s/\033\\[[0-9;]*[A-Za-z]//g')
	LC_ALL=C.UTF-8 awk 'BEGIN{print length(ARGV[1])}' "$s" 2>/dev/null \
		|| printf '%s' "$s" | LC_ALL=C.UTF-8 wc -m | awk '{print $1+0}'
}

box() {
	local text="$1"
	local len; len=$(strlen_visual "$text")
	local line; line=$(printf '═%.0s' $(seq 1 $((len + 4))))
	printf '\n%b╔%s╗%b\n'  "$C_AQUA" "$line" "$NC"
	printf '%b║%b  %b%s%b  %b║%b\n' "$C_AQUA" "$NC" "$BOLD$WHITE" "$text" "$NC" "$C_AQUA" "$NC"
	printf '%b╚%s╝%b\n\n' "$C_AQUA" "$line" "$NC"
}

panel() {
	local title="$1"; shift
	local maxlen=0 line len
	for line in "$title" "$@"; do
		len=$(strlen_visual "$line"); (( len > maxlen )) && maxlen=$len
	done
	local bar; bar=$(printf '─%.0s' $(seq 1 $((maxlen + 2))))
	printf '%b┌%s┐%b\n' "$C_TEAL" "$bar" "$NC"
	printf '%b│%b %b%s%b' "$C_TEAL" "$NC" "$BOLD" "$title" "$NC"
	printf '%*s' $((maxlen - $(strlen_visual "$title") + 1)) ''
	printf '%b│%b\n' "$C_TEAL" "$NC"
	printf '%b├%s┤%b\n' "$C_TEAL" "$bar" "$NC"
	for line in "$@"; do
		printf '%b│%b %s' "$C_TEAL" "$NC" "$line"
		printf '%*s' $((maxlen - $(strlen_visual "$line") + 1)) ''
		printf '%b│%b\n' "$C_TEAL" "$NC"
	done
	printf '%b└%s┘%b\n\n' "$C_TEAL" "$bar" "$NC"
}

hr() {
	local cols="${COLUMNS:-$(tput cols 2>/dev/null || echo 60)}"
	printf '%b' "$DIM"
	printf '─%.0s' $(seq 1 "$cols")
	printf '%b\n' "$NC"
}

confirm() {
	local prompt="$1" default="${2:-n}" reply hint_str
	[[ $default == y ]] && hint_str="[Д/n]" || hint_str="[д/Н]"
	read -rp "$(printf '  %b?%b %s %s ' "$YELLOW" "$NC" "$prompt" "$hint_str")" reply
	reply=${reply:-$default}
	[[ ${reply,,} == y* || ${reply,,} == д* ]]
}

pause() { read -n1 -r -p "$(printf '  %bНажмите любую клавишу для продолжения...%b' "$DIM" "$NC")" _; echo; }

safe_clear() { [[ -t 1 ]] && clear || true; }

# ─── Функция выбора пункта меню ────────────────────────────────────────────
# pick "Заголовок" "опция|описание" ...
# Результат → REPLY_NUM
pick() {
	local title="$1"; shift
	local i=1
	echo
	if [[ -n ${PICK_STEP:-} && -n ${PICK_TOTAL:-} ]]; then
		printf '  %b▸ [%d/%d] %s%b\n' "$BOLD$WHITE" "$PICK_STEP" "$PICK_TOTAL" "$title" "$NC"
		PICK_STEP=$((PICK_STEP + 1))
	else
		printf '  %b▸ %s%b\n' "$BOLD$WHITE" "$title" "$NC"
	fi
	printf '  %b' "$DIM"; printf '─%.0s' $(seq 1 60); printf '%b\n' "$NC"
	local opt label desc
	for opt in "$@"; do
		label="${opt%%|*}"
		if [[ "$opt" == *"|"* ]]; then
			desc="${opt#*|}"
		else
			desc=""
		fi
		printf '   %b%2d%b %b·%b %s\n' "$C_LIME" "$i" "$NC" "$DIM" "$NC" "$label"
		[[ -n $desc ]] && printf '        %b%s%b\n' "$DIM" "$desc" "$NC"
		((i++))
	done
	printf '  %b' "$DIM"; printf '─%.0s' $(seq 1 60); printf '%b\n' "$NC"
	local n=$#
	REPLY_NUM=""
	until [[ ${REPLY_NUM} =~ ^[0-9]+$ && ${REPLY_NUM} -ge 1 && ${REPLY_NUM} -le $n ]]; do
		read -rp "$(printf '\n  %b?%b Выбор [1-%d]: ' "$YELLOW" "$NC" "$n")" REPLY_NUM
	done
	echo
}

# ─── Пути и константы ──────────────────────────────────────────────────────
L2TP_CONF="/etc/xl2tpd/xl2tpd.conf"
IPSEC_CONF="/etc/ipsec.conf"
IPSEC_SECRETS="/etc/ipsec.secrets"
CHAP_SECRETS="/etc/ppp/chap-secrets"
L2TP_OPTIONS="/etc/ppp/options.xl2tpd"
USERS_REGISTRY="/etc/l2tp-menu/users"
LOG_DIR="/var/log/l2tp-menu"
INSTALLER_LOG="${LOG_DIR}/l2tp-install.log"

mkdir -p "$LOG_DIR" "$(dirname "$USERS_REGISTRY")" 2>/dev/null || true

# ─── Валидаторы ────────────────────────────────────────────────────────────
is_ipv4()    { [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
is_port()    { [[ $1 =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 )); }
is_username(){ [[ $1 =~ ^[a-zA-Z0-9_.-]+$ && ${#1} -ge 1 && ${#1} -le 63 ]]; }
is_host() {
	[[ -z $1 ]] && return 1
	is_ipv4 "$1" && return 0
	[[ $1 =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)(\.([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)){0,}$ && ${#1} -le 253 ]]
}

# ─── Генератор паролей ─────────────────────────────────────────────────────
gen_secret() {
	local len="${1:-32}"
	tr -dc 'A-Za-z0-9!@#%^&*()-_=+[]{}|' </dev/urandom 2>/dev/null | head -c "$len"
}

gen_psk() {
	# PSK без спецсимволов, вызывающих проблемы в ipsec.secrets
	tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 32
}

# ─── Предусловия ───────────────────────────────────────────────────────────
require_root() {
	if [[ ${EUID} -ne 0 ]]; then
		err "Запустите скрипт от имени root (sudo bash $0)"; exit 1
	fi
}

ensure_tools() {
	local missing=()
	for t in awk sed grep ip systemctl; do
		command -v "$t" >/dev/null 2>&1 || missing+=("$t")
	done
	if (( ${#missing[@]} > 0 )); then
		warn "Отсутствуют утилиты: ${missing[*]}. Возможны ошибки."
	fi
}

# ─── Определение ОС ────────────────────────────────────────────────────────
detect_os() {
	OS=""
	if [[ -e /etc/debian_version ]]; then
		source /etc/os-release 2>/dev/null || true
		if [[ ${ID:-} == "ubuntu" ]]; then
			OS="ubuntu"
		else
			OS="debian"
		fi
	elif [[ -e /etc/os-release ]]; then
		source /etc/os-release
		case "${ID:-}" in
			fedora)          OS="fedora" ;;
			centos|rocky|almalinux) OS="centos" ;;
			ol)              OS="oracle" ;;
			arch)            OS="arch" ;;
			opensuse-tumbleweed|opensuse-leap) OS="opensuse" ;;
			amzn)            OS="amzn" ;;
		esac
	fi
	if [[ -z $OS ]]; then
		err "Неподдерживаемая операционная система."
		err "Поддерживаются: Debian, Ubuntu, CentOS/Rocky/Alma, Fedora, openSUSE, Arch."
		exit 1
	fi
}

# ─── Установка пакетов ─────────────────────────────────────────────────────
install_packages() {
	info "Устанавливаю пакеты L2TP/IPSec..."
	case "$OS" in
		debian|ubuntu)
			apt-get update -qq
			DEBIAN_FRONTEND=noninteractive apt-get install -y \
				xl2tpd strongswan strongswan-pki \
				libcharon-extra-plugins libcharon-extauth-plugins \
				libstrongswan-extra-plugins iptables \
				2>>"$INSTALLER_LOG"
			;;
		centos|oracle|amzn)
			yum install -y xl2tpd strongswan iptables 2>>"$INSTALLER_LOG"
			;;
		fedora)
			dnf install -y xl2tpd strongswan iptables 2>>"$INSTALLER_LOG"
			;;
		opensuse)
			zypper install -y xl2tpd strongswan iptables 2>>"$INSTALLER_LOG"
			;;
		arch)
			pacman --needed --noconfirm -Syu xl2tpd strongswan iptables 2>>"$INSTALLER_LOG"
			;;
	esac
}

remove_packages() {
	info "Удаляю пакеты L2TP/IPSec..."
	case "$OS" in
		debian|ubuntu)
			apt-get remove --purge -y xl2tpd strongswan strongswan-pki \
				libcharon-extra-plugins libcharon-extauth-plugins \
				libstrongswan-extra-plugins 2>>"$INSTALLER_LOG" || true
			apt-get autoremove -y 2>>"$INSTALLER_LOG" || true
			;;
		centos|oracle|amzn)
			yum remove -y xl2tpd strongswan 2>>"$INSTALLER_LOG" || true
			;;
		fedora)
			dnf remove -y xl2tpd strongswan 2>>"$INSTALLER_LOG" || true
			;;
		opensuse)
			zypper remove -y xl2tpd strongswan 2>>"$INSTALLER_LOG" || true
			;;
		arch)
			pacman --noconfirm -R xl2tpd strongswan 2>>"$INSTALLER_LOG" || true
			;;
	esac
}

# ─── Реестр пользователей ──────────────────────────────────────────────────
register_user() {
	local username="$1"
	mkdir -p "$(dirname "$USERS_REGISTRY")" 2>/dev/null || true
	grep -Fxq "$username" "$USERS_REGISTRY" 2>/dev/null || echo "$username" >>"$USERS_REGISTRY"
}

unregister_user() {
	local username="$1"
	[[ -e $USERS_REGISTRY ]] || return 0
	local tmp
	tmp="$(mktemp)"
	grep -Fxv "$username" "$USERS_REGISTRY" >"$tmp" 2>/dev/null || true
	mv "$tmp" "$USERS_REGISTRY"
}

list_users() {
	[[ -e $USERS_REGISTRY ]] || return 0
	local users=()
	while IFS= read -r u; do
		[[ -n $u ]] && users+=("$u")
	done <"$USERS_REGISTRY"
	echo "${users[@]:-}"
}

user_exists() {
	local username="$1"
	grep -qP "^${username}\s+" "$CHAP_SECRETS" 2>/dev/null
}

# ─── Статус VPN ────────────────────────────────────────────────────────────
is_installed() {
	[[ -f "$L2TP_CONF" && -f "$IPSEC_CONF" && -f "$CHAP_SECRETS" ]]
}

count_users() {
	[[ -e $USERS_REGISTRY ]] || { echo 0; return; }
	grep -c . "$USERS_REGISTRY" 2>/dev/null || echo 0
}

status_line() {
	if is_installed; then
		local xl2tpd_svc ipsec_svc subnet
		if systemctl is-active --quiet xl2tpd 2>/dev/null; then
			xl2tpd_svc="${GREEN}● работает${NC}"
		else
			xl2tpd_svc="${RED}● остановлен${NC}"
		fi
		if systemctl is-active --quiet strongswan 2>/dev/null || \
		   systemctl is-active --quiet strongswan-starter 2>/dev/null || \
		   systemctl is-active --quiet ipsec 2>/dev/null; then
			ipsec_svc="${GREEN}● работает${NC}"
		else
			ipsec_svc="${RED}● остановлен${NC}"
		fi
		subnet=$(awk -F'=' '/ip range/{gsub(/ /,"",$2); print $2; exit}' "$L2TP_CONF" 2>/dev/null || echo "?")
		printf '  %bСостояние%b    : %bустановлен%b\n' "$BOLD" "$NC" "$GREEN" "$NC"
		printf '  %bxl2tpd%b       : %b\n' "$BOLD" "$NC" "$xl2tpd_svc"
		printf '  %bIPSec%b        : %b\n' "$BOLD" "$NC" "$ipsec_svc"
		printf '  %bПодсеть VPN%b  : %s\n' "$BOLD" "$NC" "${subnet:-?}"
		printf '  %bПользователей%b: %s\n' "$BOLD" "$NC" "$(count_users)"
	else
		printf '  %bСостояние%b    : %bне установлен%b\n' "$BOLD" "$NC" "$YELLOW" "$NC"
	fi
}

# ─── Применение sysctl ─────────────────────────────────────────────────────
apply_sysctl() {
	local f=/etc/sysctl.d/99-l2tp-ipsec.conf
	cat >"$f" <<EOF
# Добавлено l2tp-menu.sh
net.ipv4.ip_forward = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.all.rp_filter = 0
EOF
	sysctl -p "$f" >/dev/null 2>&1 || true
	ok "Параметры ядра (sysctl) настроены."
}

remove_sysctl() {
	rm -f /etc/sysctl.d/99-l2tp-ipsec.conf
	# Не сбрасываем ip_forward принудительно — это может сломать Docker, другие VPN и
	# маршрутизацию. Настройки вернутся к системным значениям при следующей перезагрузке.
	ok "Файл sysctl удалён. Параметры ядра вернутся к системным значениям после перезагрузки."
}

# ─── Настройка iptables/NAT ──────���─────────────────────────────────────────
apply_nat() {
	local subnet="$1"
	local iface
	iface=$(ip -4 route ls | awk '/^default/{print $5; exit}')
	[[ -z $iface ]] && iface=$(ip route | awk '/^default/{print $5; exit}')

	# Сохраняем правила для восстановления после перезагрузки
	local rules_file="/etc/iptables/l2tp-rules.sh"
	mkdir -p /etc/iptables
	cat >"$rules_file" <<EOF
#!/bin/bash
# Правила NAT для L2TP/IPSec (добавлено l2tp-menu.sh)
iptables -t nat -A POSTROUTING -s ${subnet}/24 -o ${iface} -j MASQUERADE
iptables -A FORWARD -s ${subnet}/24 -j ACCEPT
iptables -A FORWARD -d ${subnet}/24 -j ACCEPT
iptables -A INPUT -p udp --dport 500 -j ACCEPT
iptables -A INPUT -p udp --dport 4500 -j ACCEPT
iptables -A INPUT -p udp --dport 1701 -j ACCEPT
iptables -A INPUT -p esp -j ACCEPT
iptables -A INPUT -p ah -j ACCEPT
EOF
	chmod 700 "$rules_file"
	bash "$rules_file"

	# Автозапуск через systemd
	local svc_file="/etc/systemd/system/iptables-l2tp.service"
	cat >"$svc_file" <<EOF
[Unit]
Description=iptables rules for L2TP/IPSec
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash /etc/iptables/l2tp-rules.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
	systemctl daemon-reload
	systemctl enable iptables-l2tp 2>/dev/null || true
	ok "Правила NAT/firewall настроены (интерфейс: ${BOLD}${iface}${NC})."
}

remove_nat() {
	systemctl stop iptables-l2tp 2>/dev/null || true
	systemctl disable iptables-l2tp 2>/dev/null || true
	rm -f /etc/systemd/system/iptables-l2tp.service
	rm -f /etc/iptables/l2tp-rules.sh
	systemctl daemon-reload
	ok "Правила NAT/firewall удалены."
}

# ─── Мастер установки ──────────────────────────────────────────────────────
install_wizard() {
	box "L2TP/IPSec — пошаговая установка"
	info "Каждый параметр описан подробно. Значения по умолчанию"
	info "подходят большинству пользователей — можно просто нажимать Enter."
	echo

	PICK_STEP=1
	PICK_TOTAL=7

	# ─── 1. Публичный адрес ───
	step "Шаг 1 из 7 · Публичный адрес сервера"
	local DETECTED_IP
	DETECTED_IP=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)
	info "${BOLD}Адрес, по которому клиенты будут подключаться к серверу.${NC}"
	hint "Это публичный IP-адрес сервера или его доменное имя (например vpn.example.com)."
	hint "Если сервер за NAT/роутером — укажите внешний IP роутера и пробросьте"
	hint "порты UDP 500, 4500 и 1701 на этот сервер в настройках роутера."
	hint "Автоопределённый адрес: ${BOLD}${DETECTED_IP:-не найден}${NC}"
	local SERVER_IP=""
	read -rp "  Адрес [${DETECTED_IP}]: " SERVER_IP
	SERVER_IP="${SERVER_IP:-$DETECTED_IP}"
	if ! is_host "$SERVER_IP"; then
		err "Некорректный адрес: '$SERVER_IP'"
		return 1
	fi

	# ─── 2. Pre-Shared Key ───
	step "Шаг 2 из 7 · IPSec Pre-Shared Key (общий секрет)"
	info "${BOLD}Общий секретный ключ (пароль), которым сервер и клиент подтверждают,"
	info "что они действительно общаются друг с другом, а не с подставным узлом.${NC}"
	hint "PSK — это не пароль пользователя. Он одинаковый для всех клиентов этого сервера."
	hint "Длинный случайный PSK надёжнее короткого слова. Минимум 12 символов."
	hint "Клиенты указывают PSK в настройках VPN-соединения на своём устройстве."
	hint "Потеря PSK не страшна — его можно сменить в любой момент."
	local AUTO_PSK
	AUTO_PSK=$(gen_psk)
	local PSK=""
	read -rp "  PSK [Enter — сгенерировать автоматически]: " PSK
	PSK="${PSK:-$AUTO_PSK}"
	if [[ ${#PSK} -lt 8 ]]; then
		warn "PSK слишком короткий (менее 8 символов). Рекомендуется минимум 12."
		confirm "Всё равно использовать?" n || { PSK="$AUTO_PSK"; ok "Установлен сгенерированный PSK."; }
	fi

	# ─── 3. Подсеть VPN ───
	step "Шаг 3 из 7 · Подсеть для VPN-клиентов"
	info "${BOLD}Диапазон внутренних IP-адресов, которые получат клиенты после подключения.${NC}"
	hint "Клиенты получат адреса из этого диапазона на время VPN-сессии."
	hint "Убедитесь, что выбранная подсеть не пересекается с локальной сетью сервера."
	hint "Маска /24 означает 253 возможных клиентских адреса (достаточно для большинства)."
	pick "Подсеть для клиентов" \
		"192.168.42.0/24 ${C_GREY}(рекомендуется)${NC}|Нестандартный диапазон — минимальный риск конфликта с домашними сетями клиентов (обычно 192.168.0.x или 192.168.1.x). Шлюз сервера: 192.168.42.1." \
		"10.10.10.0/24|Корпоративный диапазон 10.x.x.x. Хорошо подходит, если клиенты не находятся в таких же подсетях. Шлюз сервера: 10.10.10.1." \
		"172.16.0.0/24|Диапазон из блока 172.16–172.31.x.x (RFC 1918). Редко используется в домашних сетях, низкий риск конфликта. Шлюз сервера: 172.16.0.1." \
		"Указать вручную|Введите начало подсети в формате X.X.X.0 (например, 10.99.0.0). Маска /24 будет применена автоматически."
	local VPN_SUBNET="" VPN_GW=""
	case "$REPLY_NUM" in
		1) VPN_SUBNET="192.168.42.0"; VPN_GW="192.168.42.1" ;;
		2) VPN_SUBNET="10.10.10.0";   VPN_GW="10.10.10.1" ;;
		3) VPN_SUBNET="172.16.0.0";   VPN_GW="172.16.0.1" ;;
		4) local s=""
		   until is_ipv4 "$s"; do read -rp "  Подсеть (X.X.X.0): " s; done
		   VPN_SUBNET="$s"
		   # Вычисляем шлюз — первый адрес подсети
		   VPN_GW="${VPN_SUBNET%.*}.1"
		   ;;
	esac

	# ─── 4. DNS-серверы ───
	step "Шаг 4 из 7 · DNS-серверы для клиентов"
	info "${BOLD}Какие DNS-серверы будут использовать клиенты во время VPN-сессии.${NC}"
	hint "DNS — это «телефонная книга» интернета: переводит имена сайтов в IP-адреса."
	hint "Выбранные серверы заменяют DNS вашего провайдера на время подключения."
	pick "DNS для клиентов" \
		"Cloudflare ${C_GREY}(1.1.1.1 / 1.0.0.1)${NC}|Самый быстрый публичный DNS в мире по независимым замерам. Не ведёт журнал запросов, поддерживает DoH и DoT. Хороший выбор по умолчанию." \
		"Quad9 ${C_GREY}(9.9.9.9 / 149.112.112.112)${NC}|Блокирует домены из базы угроз (фишинг, вредоносное ПО). Серверы в Швейцарии — хорошая юрисдикция для приватности. Рекомендуется для повышенной безопасности." \
		"Google ${C_GREY}(8.8.8.8 / 8.8.4.4)${NC}|Быстрый и надёжный, одна из крупнейших DNS-инфраструктур мира. Минус: Google ведёт журналы запросов для своей аналитики." \
		"AdGuard ${C_GREY}(94.140.14.14)${NC}|Блокирует рекламу и трекеры прямо на уровне DNS — без рекламы на всех устройствах без дополнительного ПО. Экономит трафик и заряд батареи." \
		"OpenDNS ${C_GREY}(208.67.222.222)${NC}|Один из старейших публичных DNS, принадлежит Cisco. Базовая фильтрация фишинга, высокая доступность и стабильность." \
		"Yandex ${C_GREY}(77.88.8.8 / 77.88.8.1)${NC}|Российский DNS с несколькими режимами (базовый, безопасный, семейный). Хорошая скорость для российских ресурсов." \
		"Свой DNS|Введите IP-адрес своего DNS-сервера вручную. Можно указать основной и резервный."
	local DNS1="" DNS2=""
	case "$REPLY_NUM" in
		1) DNS1="1.1.1.1";         DNS2="1.0.0.1" ;;
		2) DNS1="9.9.9.9";         DNS2="149.112.112.112" ;;
		3) DNS1="8.8.8.8";         DNS2="8.8.4.4" ;;
		4) DNS1="94.140.14.14";    DNS2="94.140.15.15" ;;
		5) DNS1="208.67.222.222";  DNS2="208.67.220.220" ;;
		6) DNS1="77.88.8.8";       DNS2="77.88.8.1" ;;
		7) local d1="" d2=""
		   until is_host "$d1"; do read -rp "  Основной DNS (IPv4): " d1; done
		   read -rp "  Дополнительный DNS (Enter — пропустить): " d2
		   DNS1="$d1"
		   is_host "$d2" && DNS2="$d2" || DNS2=""
		   ;;
	esac

	# ─── 5. Режим аутентификации ───
	step "Шаг 5 из 7 · Режим аутентификации пользователей"
	info "${BOLD}Каким способом клиенты будут подтверждать свою личность при подключении.${NC}"
	hint "Это выбор между простотой настройки на клиентских устройствах и уровнем защиты."
	pick "Режим аутентификации" \
		"Логин + пароль ${C_GREY}(CHAP, рекомендуется)${NC}|Самый распространённый и простой способ. Логин и пароль задаются на сервере и вводятся в клиентском приложении. Пароль защищён протоколом CHAP — по сети передаётся не сам пароль, а его хэш." \
		"MS-CHAPv2 ${C_GREY}(Windows-совместимость)${NC}|Протокол аутентификации от Microsoft. Обязателен для встроенного VPN-клиента Windows без сторонних программ. Менее безопасен чем CHAP при слабых паролях — используйте длинные случайные пароли." \
		"Оба метода ${C_GREY}(максимальная совместимость)${NC}|Сервер принимает как CHAP, так и MS-CHAPv2. Позволяет подключаться любым устройствам — Windows, macOS, iOS, Android. Рекомендуется если у вас разные клиентские устройства."
	local AUTH_MODE=""
	case "$REPLY_NUM" in
		1) AUTH_MODE="chap" ;;
		2) AUTH_MODE="mschapv2" ;;
		3) AUTH_MODE="both" ;;
	esac

	# ─── 6. Первый пользователь ───
	step "Шаг 6 из 7 · Создание первого пользователя VPN"
	info "${BOLD}Сразу создадим первую учётную запись для подключения к VPN.${NC}"
	hint "Каждому устройству или пользователю нужна своя учётная запись."
	hint "Логин и пароль вводятся в настройках VPN-клиента на устройстве."
	hint "Добавить ещё пользователей можно в любой момент через это меню."
	local FIRST_USER="" FIRST_PASS=""
	if confirm "Создать первого пользователя сейчас?" y; then
		until is_username "$FIRST_USER"; do
			read -rp "  Логин (a-zA-Z0-9._-, до 63 символов): " FIRST_USER
		done
		local AUTO_PASS
		AUTO_PASS=$(gen_secret 20)
		read -rp "  Пароль [Enter — сгенерировать]: " FIRST_PASS
		FIRST_PASS="${FIRST_PASS:-$AUTO_PASS}"
		if [[ ${#FIRST_PASS} -lt 8 ]]; then
			warn "Пароль короче 8 символов. Настоятельно рекомендуется использовать длиннее."
		fi
	fi

	# ─── 7. Firewall ───
	step "Шаг 7 из 7 · Правила брандмауэра"
	info "${BOLD}Нужно ли автоматически настроить iptables для работы L2TP/IPSec.${NC}"
	hint "Правила NAT позволяют клиентам выходить в интернет через сервер."
	hint "Также откроются порты UDP 500, 4500 (IPSec) и 1701 (L2TP)."
	hint "Если на сервере уже есть свой фаервол (ufw, firewalld) — добавьте правила вручную."
	hint "Если не знаете — выберите 'Да', это безопасный вариант."
	local SETUP_FW=1
	if ! confirm "Настроить iptables автоматически?" y; then
		SETUP_FW=0
	fi

	unset PICK_STEP PICK_TOTAL

	# ─── Сводка ───
	box "Проверьте параметры установки"
	local DNS_LABEL="${DNS1}"
	[[ -n $DNS2 ]] && DNS_LABEL="${DNS1}, ${DNS2}"
	local USER_LABEL="не создавать"
	[[ -n $FIRST_USER ]] && USER_LABEL="$FIRST_USER"
	local FW_LABEL="нет"; [[ $SETUP_FW -eq 1 ]] && FW_LABEL="да"
	cat <<-EOF
	  ${BOLD}Адрес сервера${NC}  : ${C_LIME}${SERVER_IP}${NC}
	  ${BOLD}PSK${NC}            : ${C_LIME}${PSK}${NC}
	  ${BOLD}Подсеть VPN${NC}    : ${C_LIME}${VPN_SUBNET}/24${NC}  ${DIM}(шлюз: ${VPN_GW})${NC}
	  ${BOLD}DNS${NC}            : ${C_LIME}${DNS_LABEL}${NC}
	  ${BOLD}Аутентификация${NC} : ${C_LIME}${AUTH_MODE}${NC}
	  ${BOLD}Первый юзер${NC}    : ${C_LIME}${USER_LABEL}${NC}
	  ${BOLD}Настроить fw${NC}   : ${FW_LABEL}
	EOF
	echo
	confirm "Начать установку?" y || { msg "  Отменено."; return 1; }

	# ─── Установка ───
	detect_os
	install_packages || { err "Ошибка установки пакетов."; return 1; }
	do_configure "$SERVER_IP" "$PSK" "$VPN_SUBNET" "$VPN_GW" "$DNS1" "$DNS2" "$AUTH_MODE"
	[[ $SETUP_FW -eq 1 ]] && apply_nat "$VPN_SUBNET"
	apply_sysctl
	start_services

	if [[ -n $FIRST_USER ]]; then
		do_add_user "$FIRST_USER" "$FIRST_PASS"
	fi

	ok "Установка завершена успешно."
	echo
	box "Параметры подключения"
	cat <<-EOF
	  ${BOLD}Адрес сервера${NC}  : ${C_LIME}${SERVER_IP}${NC}
	  ${BOLD}IPSec PSK${NC}      : ${C_LIME}${PSK}${NC}
	  ${BOLD}Тип VPN${NC}        : ${C_LIME}L2TP/IPSec с PSK${NC}
	EOF
	if [[ -n $FIRST_USER ]]; then
		cat <<-EOF
		  ${BOLD}Логин${NC}          : ${C_LIME}${FIRST_USER}${NC}
		  ${BOLD}Пароль${NC}         : ${C_LIME}${FIRST_PASS}${NC}
		EOF
	fi
	echo
	info "Эти данные также сохранены в ${BOLD}/etc/l2tp-menu/credentials.txt${NC}"
	{
		echo "# L2TP/IPSec параметры подключения"
		echo "# Сгенерировано: $(date)"
		echo "Адрес сервера : ${SERVER_IP}"
		echo "IPSec PSK     : ${PSK}"
		echo "Тип VPN       : L2TP/IPSec с PSK"
		[[ -n $FIRST_USER ]] && echo "Логин         : ${FIRST_USER}"
		[[ -n $FIRST_USER ]] && echo "Пароль        : ${FIRST_PASS}"
	} > /etc/l2tp-menu/credentials.txt
	chmod 600 /etc/l2tp-menu/credentials.txt
}

# ─── Генерация конфигурационных файлов ─────────────────────────────────────
do_configure() {
	local server_ip="$1" psk="$2" subnet="$3" gw="$4"
	local dns1="$5" dns2="$6" auth_mode="$7"

	# Диапазон адресов пула клиентов (2-254)
	local net_prefix="${subnet%.*}"
	local pool_start="${net_prefix}.10"
	local pool_end="${net_prefix}.254"

	info "Записываю конфигурацию xl2tpd..."
	mkdir -p /etc/xl2tpd
	cat >"/etc/xl2tpd/xl2tpd.conf" <<EOF
[global]
ipsec saref = yes
saref refinfo = 30

[lns default]
ip range = ${pool_start}-${pool_end}
local ip = ${gw}
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

	info "Записываю конфигурацию IPSec (strongSwan)..."
	cat >"/etc/ipsec.conf" <<EOF
config setup
    uniqueids = no
    charondebug = "ike 1, knl 1, cfg 0"

conn L2TP-PSK-NAT
    rightsubnet = vhost:%priv
    also = L2TP-PSK-noNAT

conn L2TP-PSK-noNAT
    authby = secret
    auto = add
    keyingtries = 3
    rekey = no
    ikelifetime = 8h
    keylife = 1h
    type = transport
    left = %defaultroute
    leftid = ${server_ip}
    leftprotoport = 17/1701
    right = %any
    rightprotoport = 17/%any
    dpddelay = 30
    dpdtimeout = 120
    dpdaction = clear
    ike = aes256-sha2_256-modp2048,aes256-sha2_256-modp1536,aes256-sha1-modp2048!
    esp = aes256-sha2_256,aes256-sha1!
EOF

	info "Записываю PSK в /etc/ipsec.secrets..."
	cat >"/etc/ipsec.secrets" <<EOF
# Управляется l2tp-menu.sh
%any %any : PSK "${psk}"
EOF
	chmod 600 /etc/ipsec.secrets

	info "Настраиваю PPP-опции..."
	mkdir -p /etc/ppp
	local auth_opts=""
	case "$auth_mode" in
		chap)     auth_opts="require-chap\nrefuse-pap\nrefuse-mschap\nrefuse-mschap-v2" ;;
		mschapv2) auth_opts="require-mschap-v2\nrefuse-pap\nrefuse-chap\nrefuse-mschap" ;;
		both)     auth_opts="require-chap\nrequire-mschap-v2\nrefuse-pap" ;;
	esac
	printf "# PPP-опции для L2TP/IPSec (управляется l2tp-menu.sh)\nipcp-accept-local\nipcp-accept-remote\nms-dns %s\n" "$dns1" >"$L2TP_OPTIONS"
	[[ -n $dns2 ]] && printf "ms-dns %s\n" "$dns2" >>"$L2TP_OPTIONS"
	printf "noccp\nauth\ncrtscts\nmtu 1410\nmru 1410\nnodefaultroute\nlock\nproxyarp\nlcp-echo-failure 4\nlcp-echo-interval 30\nconnect-delay 5000\n%b\n" "$(printf '%b' "$auth_opts")" >>"$L2TP_OPTIONS"

	# Создаём файл chap-secrets если его нет
	[[ -f /etc/ppp/chap-secrets ]] || printf "# Managed by l2tp-menu.sh\n# username\tserver\tpassword\tip\n" >"/etc/ppp/chap-secrets"
	chmod 600 /etc/ppp/chap-secrets

	ok "Конфигурационные файлы созданы."
}

# ─── Управление службами ───────────────────────────────────────────────────
start_services() {
	info "Запускаю службы IPSec и L2TP..."
	# strongSwan может называться по-разному
	if systemctl list-unit-files strongswan.service &>/dev/null; then
		systemctl enable strongswan  2>/dev/null && systemctl restart strongswan  || true
	elif systemctl list-unit-files strongswan-starter.service &>/dev/null; then
		systemctl enable strongswan-starter 2>/dev/null && systemctl restart strongswan-starter || true
	else
		systemctl enable ipsec 2>/dev/null && systemctl restart ipsec || true
	fi
	systemctl enable xl2tpd 2>/dev/null && systemctl restart xl2tpd
	sleep 1
	local ok_ipsec=0 ok_l2tp=0
	if systemctl is-active --quiet strongswan 2>/dev/null \
		|| systemctl is-active --quiet strongswan-starter 2>/dev/null \
		|| systemctl is-active --quiet ipsec 2>/dev/null; then
		ok_ipsec=1
	fi
	systemctl is-active --quiet xl2tpd 2>/dev/null && ok_l2tp=1
	(( ok_ipsec )) && ok "IPSec (strongSwan): работает." || warn "IPSec не запустился. Проверьте: journalctl -u strongswan"
	(( ok_l2tp ))  && ok "xl2tpd: работает."              || warn "xl2tpd не запустился. Проверьте: journalctl -u xl2tpd"
}

restart_services() {
	info "Перезапускаю службы..."
	systemctl restart strongswan 2>/dev/null \
		|| systemctl restart strongswan-starter 2>/dev/null \
		|| systemctl restart ipsec 2>/dev/null || true
	systemctl restart xl2tpd
	ok "Службы перезапущены."
}

# ─── Управление пользователями ─────────────────────────────────────────────
do_add_user() {
	local username="$1" password="$2"
	# Добавляем в chap-secrets (формат: username * password *)
	# Проверяем дублирование
	if grep -qP "^${username}\s" /etc/ppp/chap-secrets 2>/dev/null; then
		warn "Пользователь '${username}' уже существует. Обновляю пароль..."
		sed -i "/^${username}\s/d" /etc/ppp/chap-secrets
	fi
	printf '%s\t*\t"%s"\t*\n' "$username" "$password" >>/etc/ppp/chap-secrets
	register_user "$username"
	ok "Пользователь ${BOLD}${username}${NC} добавлен."
	info "  Логин   : ${BOLD}${username}${NC}"
	info "  Пароль  : ${BOLD}${password}${NC}"
}

user_add() {
	box "Добавление пользователя VPN"
	info "Создаётся учётная запись для подключения к L2TP/IPSec VPN."
	info "Каждое устройство рекомендуется заводить под отдельным логином —"
	info "это упрощает управление доступом и отключение конкретного устройства."
	echo
	local username=""
	until is_username "$username"; do
		read -rp "  Логин (a-zA-Z0-9._-, до 63 символов): " username
	done
	if grep -qP "^${username}\s" /etc/ppp/chap-secrets 2>/dev/null; then
		warn "Пользователь '${username}' уже существует."
		confirm "Обновить пароль?" n || return 0
	fi
	local AUTO_PASS
	AUTO_PASS=$(gen_secret 20)
	local password=""
	read -rp "  Пароль [Enter — сгенерировать автоматически]: " password
	password="${password:-$AUTO_PASS}"
	if [[ ${#password} -lt 8 ]]; then
		warn "Пароль слишком короткий. Рекомендуется минимум 12 символов."
		confirm "Всё равно использовать?" n || { password="$AUTO_PASS"; ok "Установлен сгенерированный пароль."; }
	fi
	do_add_user "$username" "$password"
}

user_delete() {
	box "Удаление пользователя VPN"
	info "После удаления пользователь немедленно потеряет доступ к VPN."
	info "Активные сессии этого пользователя будут разорваны."
	echo
	if [[ ! -s $USERS_REGISTRY ]]; then
		warn "Нет зарегистрированных пользователей."
		return 0
	fi
	local userlist=()
	while IFS= read -r u; do [[ -n $u ]] && userlist+=("$u"); done <"$USERS_REGISTRY"
	local opts=()
	for u in "${userlist[@]}"; do opts+=("${u}|Логин: ${u}"); done
	opts+=("← Отмена|")
	pick "Выберите пользователя для удаления" "${opts[@]}"
	(( REPLY_NUM == ${#opts[@]} )) && return 0
	local target="${userlist[$((REPLY_NUM-1))]}"
	confirm "Удалить пользователя '${target}'? Действие необратимо." n || return 0
	sed -i "/^${target}\s/d" /etc/ppp/chap-secrets
	unregister_user "$target"
	ok "Пользователь ${BOLD}${target}${NC} удалён."
}

user_change_password() {
	box "Смена пароля пользователя"
	info "Изменить пароль существующего пользователя VPN."
	info "Новый пароль вступит в силу при следующем подключении."
	echo
	if [[ ! -s $USERS_REGISTRY ]]; then
		warn "Нет зарегистрированных пользователей."
		return 0
	fi
	local userlist=()
	while IFS= read -r u; do [[ -n $u ]] && userlist+=("$u"); done <"$USERS_REGISTRY"
	local opts=()
	for u in "${userlist[@]}"; do opts+=("${u}|"); done
	opts+=("← Отмена|")
	pick "Выберите пользователя" "${opts[@]}"
	(( REPLY_NUM == ${#opts[@]} )) && return 0
	local target="${userlist[$((REPLY_NUM-1))]}"
	local AUTO_PASS
	AUTO_PASS=$(gen_secret 20)
	local newpass=""
	read -rp "  Новый пароль [Enter — сгенерировать]: " newpass
	newpass="${newpass:-$AUTO_PASS}"
	sed -i "/^${target}\s/d" /etc/ppp/chap-secrets
	printf '%s\t*\t"%s"\t*\n' "$target" "$newpass" >>/etc/ppp/chap-secrets
	ok "Пароль пользователя ${BOLD}${target}${NC} изменён."
	info "  Новый пароль: ${BOLD}${newpass}${NC}"
}

user_list() {
	box "Список пользователей VPN"
	if [[ ! -s $USERS_REGISTRY ]]; then
		warn "Пользователи не найдены. Добавьте первого пользователя через меню."
		return 0
	fi
	printf '  %b%-25s  %-30s%b\n' "$BOLD" "Логин" "Пароль" "$NC"
	printf '  %b' "$DIM"; printf '─%.0s' $(seq 1 60); printf '%b\n' "$NC"
	while IFS= read -r u; do
		[[ -z $u ]] && continue
		local pw
		pw=$(awk -v user="$u" 'BEGIN{IGNORECASE=0} $1==user{gsub(/"/, "", $3); print $3; exit}' /etc/ppp/chap-secrets 2>/dev/null || echo "?")
		printf '  %-25s  %s\n' "$u" "${pw:-?}"
	done <"$USERS_REGISTRY"
	printf '  %b' "$DIM"; printf '─%.0s' $(seq 1 60); printf '%b\n' "$NC"
}

# ─── Меню пользователей ────────────────────────────────────────────────────
users_menu() {
	while true; do
		safe_clear
		box "Управление пользователями VPN"
		pick "Выберите действие" \
			"Добавить пользователя|Создать новую учётную запись для подключения к VPN. Каждому устройству рекомендуется отдельный логин." \
			"Список пользователей|Показать всех зарегистрированных пользователей и их пароли." \
			"Сменить пароль|Изменить пароль существующего пользователя. Новый пароль вступит в силу при следующем подключении." \
			"Удалить пользователя|Немедленно отозвать доступ. Активные сессии будут разорваны." \
			"← Вернуться в главное меню|"
		case "$REPLY_NUM" in
			1) user_add ;;
			2) user_list ;;
			3) user_change_password ;;
			4) user_delete ;;
			5) return ;;
		esac
		pause
	done
}

# ─── Меню сервера ──────────────────────────────────────────────────────────
server_menu() {
	while true; do
		safe_clear
		box "Управление сервером L2TP/IPSec"
		pick "Выберите действие" \
			"Перезапустить службы|Выполнить restart для IPSec (strongSwan) и xl2tpd. Нужно после ручного редактирования конфигов или смены PSK." \
			"Сменить PSK|Изменить IPSec Pre-Shared Key. После смены все клиенты должны обновить PSK в настройках своего VPN-соединения." \
			"Показать параметры подключения|Вывести адрес сервера, PSK и инструкцию для подключения клиентов." \
			"Активные сессии PPP|Показать список активных PPP-соединений (подключённых клиентов)." \
			"← Вернуться в главное меню|"
		case "$REPLY_NUM" in
			1) restart_services ;;
			2) change_psk ;;
			3) show_connection_info ;;
			4) show_active_sessions ;;
			5) return ;;
		esac
		pause
	done
}

change_psk() {
	box "Смена IPSec Pre-Shared Key"
	warn "После смены PSK все клиенты должны вручную обновить PSK в настройках VPN."
	info "Активные соединения будут разорваны при ближайшем переподключении."
	echo
	local AUTO_PSK
	AUTO_PSK=$(gen_psk)
	local new_psk=""
	read -rp "  Новый PSK [Enter — сгенерировать]: " new_psk
	new_psk="${new_psk:-$AUTO_PSK}"
	if [[ ${#new_psk} -lt 8 ]]; then
		warn "PSK короче 8 символов."
		confirm "Всё равно использовать?" n || { new_psk="$AUTO_PSK"; ok "Установлен сгенерированный PSK."; }
	fi
	# Обновляем ipsec.secrets
	printf '# Управляется l2tp-menu.sh\n%%any %%any : PSK "%s"\n' "$new_psk" >"/etc/ipsec.secrets"
	chmod 600 /etc/ipsec.secrets
	restart_services
	ok "PSK изменён: ${BOLD}${new_psk}${NC}"
	info "Сообщите новый PSK всем клиентам и попросите обновить настройки VPN."
}

show_connection_info() {
	box "Параметры подключения"
	local server_ip psk
	server_ip=$(awk '/leftid/{print $3}' "$IPSEC_CONF" 2>/dev/null | head -1)
	psk=$(grep ': PSK ' "$IPSEC_SECRETS" 2>/dev/null | sed 's/.*PSK "\(.*\)".*/\1/')
	panel "Параметры подключения L2TP/IPSec" \
		"Тип VPN       : L2TP/IPSec с Pre-Shared Key (PSK)" \
		"Адрес сервера : ${server_ip:-смотри ipsec.conf}" \
		"IPSec PSK     : ${psk:-смотри /etc/ipsec.secrets}" \
		"Аутентификация: Имя пользователя + пароль (PPP/CHAP)"
	info "Клиентские приложения: встроенный VPN в Windows / macOS / iOS / Android."
	hint "Windows: Панель управления → Сеть → Новое VPN-подключение → Тип: L2TP/IPSec с PSK"
	hint "iOS/Android: Настройки → VPN → Добавить → L2TP → ввести адрес, PSK, логин, пароль"
}

show_active_sessions() {
	box "Активные PPP-сессии"
	info "Список текущих PPP-интерфейсов (ppp0, ppp1, ...):"
	echo
	if ip link show | grep -q 'ppp'; then
		ip link show | awk '/ppp[0-9]/{print "  " $2}' | sed 's/://'
		echo
		info "Подробнее: ${BOLD}ip addr show${NC} или ${BOLD}last -w${NC}"
	else
		warn "Активных PPP-сессий не обнаружено."
		hint "Если клиент только что подключился, подождите несколько секунд."
	fi
}

# ─── Удаление ──────────────────────────────────────────────────────────────
uninstall() {
	box "Удаление L2TP/IPSec"
	warn "ВНИМАНИЕ: Это необратимое действие!"
	warn "Будут удалены: xl2tpd, strongSwan, все конфиги, все учётные записи VPN."
	warn "Правила iptables для L2TP/IPSec также будут удалены."
	info "После удаления ни один клиент не сможет подключиться к этому серверу."
	echo
	if ! confirm "Действительно полностью удалить L2TP/IPSec?" n; then
		msg "  Удаление отменено."
		return 1
	fi
	detect_os
	# Останавливаем службы
	systemctl stop xl2tpd 2>/dev/null || true
	systemctl stop strongswan 2>/dev/null || true
	systemctl stop strongswan-starter 2>/dev/null || true
	systemctl stop ipsec 2>/dev/null || true
	systemctl disable xl2tpd 2>/dev/null || true
	systemctl disable strongswan 2>/dev/null || true
	systemctl disable strongswan-starter 2>/dev/null || true
	systemctl disable ipsec 2>/dev/null || true
	# Удаляем NAT-правила
	remove_nat
	# Удаляем sysctl
	remove_sysctl
	# Удаляем пакеты
	remove_packages
	# Удаляем конфиги
	rm -f /etc/xl2tpd/xl2tpd.conf
	rm -f /etc/ipsec.conf /etc/ipsec.secrets
	rm -f /etc/ppp/options.xl2tpd
	# chap-secrets не удаляем полностью — там могут быть записи других сервисов
	ok "Конфиги удалены."
	# Удаляем метаданные скрипта
	rm -rf /etc/l2tp-menu
	rm -rf "$LOG_DIR"
	ok "L2TP/IPSec полностью удалён."
	return 0
}

# ─── Баннер ────────────────────────────────────────────────────────────────
banner() {
	cat <<EOF
${C_AQUA}    ╔════════════════════════════════════════════════════════════════╗${NC}
${C_AQUA}    ║${NC}   ${C_PINK}██╗     ██████╗ ████████╗██████╗ ${NC}   ${C_LIME}██╗██████╗ ███████╗███████╗ ██████╗${NC}  ${C_AQUA}║${NC}
${C_AQUA}    ║${NC}   ${C_PINK}██║     ╚════██╗╚══██╔══╝██╔══██╗${NC}   ${C_LIME}██║██╔══██╗██╔════╝██╔════╝██╔════╝${NC}  ${C_AQUA}║${NC}
${C_AQUA}    ║${NC}   ${C_PINK}██║      █████╔╝   ██║   ██████╔╝${NC}   ${C_LIME}██║██████╔╝███████╗█████╗  ██║     ${NC}  ${C_AQUA}║${NC}
${C_AQUA}    ║${NC}   ${C_PINK}██║     ██╔═══╝    ██║   ██╔═══╝ ${NC}   ${C_LIME}██║██╔═══╝ ╚════██║██╔══╝  ██║     ${NC}  ${C_AQUA}║${NC}
${C_AQUA}    ║${NC}   ${C_PINK}███████╗███████╗   ██║   ██║     ${NC}   ${C_LIME}██║██║     ███████║███████╗╚██████╗${NC}  ${C_AQUA}║${NC}
${C_AQUA}    ║${NC}   ${C_PINK}╚══════╝╚══════╝   ╚═╝   ╚═╝     ${NC}   ${C_LIME}╚═╝╚═╝     ╚══════╝╚══════╝ ╚═════╝${NC}  ${C_AQUA}║${NC}
${C_AQUA}    ╚════════════════════════════════════════════════════════════════╝${NC}
         ${DIM}Меню установки и управления L2TP/IPSec${NC}  ${C_ORANGE}v${SCRIPT_VERSION}${NC}
EOF
}

# ─── Главное меню ──────────────────────────────────────────────────────────
main_menu() {
	while true; do
		safe_clear
		banner
		box "Главное меню"
		status_line
		echo
		if is_installed; then
			pick "Выберите действие" \
				"Управление пользователями|Добавить нового пользователя, сменить пароль, удалить учётную запись, просмотреть список." \
				"Управление сервером|Перезапуск служб, смена PSK, активные сессии, параметры подключения для кли��нтов." \
				"Переустановить L2TP/IPSec|Удалить текущую установку и запустить мастер установки заново с новыми параметрами." \
				"Удалить L2TP/IPSec|Полностью удалить службы, конфиги и все учётные записи с этого сервера." \
				"Выход|Закрыть это меню. VPN-службы продолжат работать в фоне."
			case "$REPLY_NUM" in
				1) users_menu ;;
				2) server_menu ;;
				3) if uninstall; then
				       install_wizard || warn "Установка не выполнена."
				   else
				       msg "  Переустановка отменена."
				   fi ;;
				4) uninstall || true ;;
				5) safe_clear; exit 0 ;;
			esac
		else
			pick "Выберите действие" \
				"Установить L2TP/IPSec — пошаговый мастер|Удобный мастер с подробными русскоязычными подсказками к каждому шагу. Рекомендуется для первой установки." \
				"Показать параметры подключения|Вывести данные для подключения клиентов (адрес, PSK, логин/пароль) из сохранённого файла." \
				"Выход|Закрыть это меню."
			case "$REPLY_NUM" in
				1) install_wizard || true ;;
				2) if [[ -f /etc/l2tp-menu/credentials.txt ]]; then
				       box "Сохранённые параметры подключения"
				       cat /etc/l2tp-menu/credentials.txt | sed 's/^/  /'
				   else
				       warn "L2TP/IPSec не установлен или файл параметров не найден."
				   fi ;;
				3) safe_clear; exit 0 ;;
			esac
		fi
		echo
		pause
	done
}

# ─── Точка входа ───────────────────────────────────────────────────────────
require_root
ensure_tools
main_menu
exit 0
