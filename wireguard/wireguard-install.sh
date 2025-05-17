#!/bin/bash

# Настройка WireGuard только с IPv4 (модифицированный скрипт)

RED='\033[0;31m'
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'

function isRoot() {
	if [ "${EUID}" -ne 0 ]; then
		echo "Скрипт должен быть запущен с правами root"
		exit 1
	fi
}

function checkVirt() {
	function openvzErr() {
		echo "OpenVZ не поддерживается"
		exit 1
	}
	function lxcErr() {
		echo "LXC не поддерживается (пока)."
		echo "WireGuard технически может работать в контейнере LXC,"
		echo "но модуль ядра должен быть установлен на хосте,"
		echo "контейнер должен быть запущен с определенными параметрами"
		echo "и только утилиты должны быть установлены в контейнере."
		exit 1
	}
	if command -v virt-what &>/dev/null; then
		if [ "$(virt-what)" == "openvz" ]; then
			openvzErr
		fi
		if [ "$(virt-what)" == "lxc" ]; then
			lxcErr
		fi
	else
		if [ "$(systemd-detect-virt)" == "openvz" ]; then
			openvzErr
		fi
		if [ "$(systemd-detect-virt)" == "lxc" ]; then
			lxcErr
		fi
	fi
}

function checkOS() {
	source /etc/os-release
	OS="${ID}"
	if [[ ${OS} == "debian" || ${OS} == "raspbian" ]]; then
		if [[ ${VERSION_ID} -lt 10 ]]; then
			echo "Ваша версия Debian (${VERSION_ID}) не поддерживается. Используйте Debian 10 Buster или новее"
			exit 1
		fi
		OS=debian # перезаписываем, если raspbian
	elif [[ ${OS} == "ubuntu" ]]; then
		RELEASE_YEAR=$(echo "${VERSION_ID}" | cut -d'.' -f1)
		if [[ ${RELEASE_YEAR} -lt 18 ]]; then
			echo "Ваша версия Ubuntu (${VERSION_ID}) не поддерживается. Используйте Ubuntu 18.04 или новее"
			exit 1
		fi
	elif [[ ${OS} == "fedora" ]]; then
		if [[ ${VERSION_ID} -lt 32 ]]; then
			echo "Ваша версия Fedora (${VERSION_ID}) не поддерживается. Используйте Fedora 32 или новее"
			exit 1
		fi
	elif [[ ${OS} == 'centos' ]] || [[ ${OS} == 'almalinux' ]] || [[ ${OS} == 'rocky' ]]; then
		if [[ ${VERSION_ID} == 7* ]]; then
			echo "Ваша версия CentOS (${VERSION_ID}) не поддерживается. Используйте CentOS 8 или новее"
			exit 1
		fi
	elif [[ -e /etc/oracle-release ]]; then
		source /etc/os-release
		OS=oracle
	elif [[ -e /etc/arch-release ]]; then
		OS=arch
	elif [[ -e /etc/alpine-release ]]; then
		OS=alpine
		if ! command -v virt-what &>/dev/null; then
			apk update && apk add virt-what
		fi
	else
		echo "Похоже, вы не используете Debian, Ubuntu, Fedora, CentOS, AlmaLinux, Oracle или Arch Linux"
		exit 1
	fi
}

function getHomeDirForClient() {
	local CLIENT_NAME=$1

	if [ -z "${CLIENT_NAME}" ]; then
		echo "Ошибка: getHomeDirForClient() требует имя клиента в качестве аргумента"
		exit 1
	fi

	# Домашний каталог пользователя, куда будет записана конфигурация клиента
	if [ -e "/home/${CLIENT_NAME}" ]; then
		# если $1 - имя пользователя
		HOME_DIR="/home/${CLIENT_NAME}"
	elif [ "${SUDO_USER}" ]; then
		# если нет, используем SUDO_USER
		if [ "${SUDO_USER}" == "root" ]; then
			# Если sudo запущен от root
			HOME_DIR="/root"
		else
			HOME_DIR="/home/${SUDO_USER}"
		fi
	else
		# если нет SUDO_USER, используем /root
		HOME_DIR="/root"
	fi

	echo "$HOME_DIR"
}

function initialCheck() {
	isRoot
	checkOS
	checkVirt
}

function installQuestions() {
	echo "Добро пожаловать в установщик WireGuard (только IPv4)!"
	echo ""
	echo "Я задам несколько вопросов перед началом установки."
	echo "Вы можете оставить значения по умолчанию, нажав Enter, если они вас устраивают."
	echo ""

	# Определение публичного IPv4 адреса и предварительное заполнение для пользователя
	SERVER_PUB_IP=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | awk '{print $1}' | head -1)
	
	read -rp "Публичный IPv4 адрес: " -e -i "${SERVER_PUB_IP}" SERVER_PUB_IP

	# Определение публичного интерфейса и предварительное заполнение для пользователя
	SERVER_NIC="$(ip -4 route ls | grep default | awk '/dev/ {for (i=1; i<=NF; i++) if ($i == "dev") print $(i+1)}' | head -1)"
	until [[ ${SERVER_PUB_NIC} =~ ^[a-zA-Z0-9_]+$ ]]; do
		read -rp "Публичный интерфейс: " -e -i "${SERVER_NIC}" SERVER_PUB_NIC
	done

	until [[ ${SERVER_WG_NIC} =~ ^[a-zA-Z0-9_]+$ && ${#SERVER_WG_NIC} -lt 16 ]]; do
		read -rp "Имя интерфейса WireGuard: " -e -i wg0 SERVER_WG_NIC
	done

	until [[ ${SERVER_WG_IPV4} =~ ^([0-9]{1,3}\.){3} ]]; do
		read -rp "IPv4 адрес сервера WireGuard: " -e -i 10.66.66.1 SERVER_WG_IPV4
	done

	# Генерация случайного номера в диапазоне частных портов
	RANDOM_PORT=$(shuf -i49152-65535 -n1)
	until [[ ${SERVER_PORT} =~ ^[0-9]+$ ]] && [ "${SERVER_PORT}" -ge 1 ] && [ "${SERVER_PORT}" -le 65535 ]; do
		read -rp "Порт сервера WireGuard [1-65535]: " -e -i "${RANDOM_PORT}" SERVER_PORT
	done

	# DNS по умолчанию - Cloudflare
	until [[ ${CLIENT_DNS_1} =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; do
		read -rp "Первый DNS-сервер для клиентов: " -e -i 1.1.1.1 CLIENT_DNS_1
	done
	until [[ ${CLIENT_DNS_2} =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; do
		read -rp "Второй DNS-сервер для клиентов (опционально): " -e -i 1.0.0.1 CLIENT_DNS_2
		if [[ ${CLIENT_DNS_2} == "" ]]; then
			CLIENT_DNS_2="${CLIENT_DNS_1}"
		fi
	done

	# ТОЛЬКО IPv4 для AllowedIPs
	ALLOWED_IPS="0.0.0.0/0"
	echo -e "\nWireGuard использует параметр AllowedIPs для определения того, что маршрутизируется через VPN."
	echo -e "Установлено значение для маршрутизации всего IPv4 трафика через VPN: '${ALLOWED_IPS}'"

	echo ""
	echo "Отлично, это все, что мне нужно. Теперь я настрою ваш сервер WireGuard только с поддержкой IPv4."
	echo "Вы сможете создать клиента в конце установки."
	read -n1 -r -p "Нажмите любую клавишу для продолжения..."
}

function installWireGuard() {
	# Сначала выполнить вопросы по установке
	installQuestions

	# Установка инструментов WireGuard и модуля
	if [[ ${OS} == 'ubuntu' ]] || [[ ${OS} == 'debian' && ${VERSION_ID} -gt 10 ]]; then
		apt-get update
		apt-get install -y wireguard iptables resolvconf qrencode
	elif [[ ${OS} == 'debian' ]]; then
		if ! grep -rqs "^deb .* buster-backports" /etc/apt/; then
			echo "deb http://deb.debian.org/debian buster-backports main" >/etc/apt/sources.list.d/backports.list
			apt-get update
		fi
		apt update
		apt-get install -y iptables resolvconf qrencode
		apt-get install -y -t buster-backports wireguard
	elif [[ ${OS} == 'fedora' ]]; then
		if [[ ${VERSION_ID} -lt 32 ]]; then
			dnf install -y dnf-plugins-core
			dnf copr enable -y jdoss/wireguard
			dnf install -y wireguard-dkms
		fi
		dnf install -y wireguard-tools iptables qrencode
	elif [[ ${OS} == 'centos' ]] || [[ ${OS} == 'almalinux' ]] || [[ ${OS} == 'rocky' ]]; then
		if [[ ${VERSION_ID} == 8* ]]; then
			yum install -y epel-release elrepo-release
			yum install -y kmod-wireguard
			yum install -y qrencode # не доступно в релизе 9
		fi
		yum install -y wireguard-tools iptables
	elif [[ ${OS} == 'oracle' ]]; then
		dnf install -y oraclelinux-developer-release-el8
		dnf config-manager --disable -y ol8_developer
		dnf config-manager --enable -y ol8_developer_UEKR6
		dnf config-manager --save -y --setopt=ol8_developer_UEKR6.includepkgs='wireguard-tools*'
		dnf install -y wireguard-tools qrencode iptables
	elif [[ ${OS} == 'arch' ]]; then
		pacman -S --needed --noconfirm wireguard-tools qrencode
	elif [[ ${OS} == 'alpine' ]]; then
		apk update
		apk add wireguard-tools iptables build-base libpng-dev
		curl -O https://fukuchi.org/works/qrencode/qrencode-4.1.1.tar.gz
		tar xf qrencode-4.1.1.tar.gz
		(cd qrencode-4.1.1 || exit && ./configure && make && make install && ldconfig)
	fi

	# Убедимся, что директория существует (может отсутствовать на федоре)
	mkdir /etc/wireguard >/dev/null 2>&1

	chmod 600 -R /etc/wireguard/

	SERVER_PRIV_KEY=$(wg genkey)
	SERVER_PUB_KEY=$(echo "${SERVER_PRIV_KEY}" | wg pubkey)

	# Сохранить настройки WireGuard
	echo "SERVER_PUB_IP=${SERVER_PUB_IP}
SERVER_PUB_NIC=${SERVER_PUB_NIC}
SERVER_WG_NIC=${SERVER_WG_NIC}
SERVER_WG_IPV4=${SERVER_WG_IPV4}
SERVER_PORT=${SERVER_PORT}
SERVER_PRIV_KEY=${SERVER_PRIV_KEY}
SERVER_PUB_KEY=${SERVER_PUB_KEY}
CLIENT_DNS_1=${CLIENT_DNS_1}
CLIENT_DNS_2=${CLIENT_DNS_2}
ALLOWED_IPS=${ALLOWED_IPS}" >/etc/wireguard/params

	# Добавление интерфейса сервера
	echo "[Interface]
Address = ${SERVER_WG_IPV4}/24
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIV_KEY}" >"/etc/wireguard/${SERVER_WG_NIC}.conf"

	if pgrep firewalld; then
		FIREWALLD_IPV4_ADDRESS=$(echo "${SERVER_WG_IPV4}" | cut -d"." -f1-3)".0"
		echo "PostUp = firewall-cmd --zone=public --add-interface=${SERVER_WG_NIC} && firewall-cmd --add-port ${SERVER_PORT}/udp && firewall-cmd --add-rich-rule='rule family=ipv4 source address=${FIREWALLD_IPV4_ADDRESS}/24 masquerade'
PostDown = firewall-cmd --zone=public --remove-interface=${SERVER_WG_NIC} && firewall-cmd --remove-port ${SERVER_PORT}/udp && firewall-cmd --remove-rich-rule='rule family=ipv4 source address=${FIREWALLD_IPV4_ADDRESS}/24 masquerade'" >>"/etc/wireguard/${SERVER_WG_NIC}.conf"
	else
		echo "PostUp = iptables -I INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT
PostUp = iptables -I FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT
PostUp = iptables -I FORWARD -i ${SERVER_WG_NIC} -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
PostDown = iptables -D INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT
PostDown = iptables -D FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT
PostDown = iptables -D FORWARD -i ${SERVER_WG_NIC} -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE" >>"/etc/wireguard/${SERVER_WG_NIC}.conf"
	fi

	# Включение маршрутизации на сервере (только IPv4)
	echo "net.ipv4.ip_forward = 1" >/etc/sysctl.d/wg.conf

	if [[ ${OS} == 'alpine' ]]; then
		sysctl -p /etc/sysctl.d/wg.conf
		rc-update add sysctl
		ln -s /etc/init.d/wg-quick "/etc/init.d/wg-quick.${SERVER_WG_NIC}"
		rc-service "wg-quick.${SERVER_WG_NIC}" start
		rc-update add "wg-quick.${SERVER_WG_NIC}"
	else
		sysctl --system

		systemctl start "wg-quick@${SERVER_WG_NIC}"
		systemctl enable "wg-quick@${SERVER_WG_NIC}"
	fi

	newClient
	echo -e "${GREEN}Если вы хотите добавить больше клиентов, просто запустите этот скрипт еще раз!${NC}"

	# Проверка, запущен ли WireGuard
	if [[ ${OS} == 'alpine' ]]; then
		rc-service --quiet "wg-quick.${SERVER_WG_NIC}" status
	else
		systemctl is-active --quiet "wg-quick@${SERVER_WG_NIC}"
	fi
	WG_RUNNING=$?

	# WireGuard может не работать, если мы обновили ядро. Сообщить пользователю о необходимости перезагрузки
	if [[ ${WG_RUNNING} -ne 0 ]]; then
		echo -e "\n${RED}ВНИМАНИЕ: WireGuard, похоже, не запущен.${NC}"
		if [[ ${OS} == 'alpine' ]]; then
			echo -e "${ORANGE}Вы можете проверить, работает ли WireGuard, с помощью: rc-service wg-quick.${SERVER_WG_NIC} status${NC}"
		else
			echo -e "${ORANGE}Вы можете проверить, работает ли WireGuard, с помощью: systemctl status wg-quick@${SERVER_WG_NIC}${NC}"
		fi
		echo -e "${ORANGE}Если вы видите что-то вроде \"Cannot find device ${SERVER_WG_NIC}\", пожалуйста, перезагрузите систему!${NC}"
	else # WireGuard запущен
		echo -e "\n${GREEN}WireGuard запущен.${NC}"
		if [[ ${OS} == 'alpine' ]]; then
			echo -e "${GREEN}Вы можете проверить статус WireGuard с помощью: rc-service wg-quick.${SERVER_WG_NIC} status\n\n${NC}"
		else
			echo -e "${GREEN}Вы можете проверить статус WireGuard с помощью: systemctl status wg-quick@${SERVER_WG_NIC}\n\n${NC}"
		fi
		echo -e "${ORANGE}Если у вас нет доступа к интернету из клиента, попробуйте перезагрузить сервер.${NC}"
	fi
}

function newClient() {
	echo ""
	echo "Конфигурация клиента"
	echo ""
	echo "Имя клиента должно состоять из буквенно-цифровых символов. Оно также может включать подчеркивания или дефисы и не должно превышать 15 символов."

	until [[ ${CLIENT_NAME} =~ ^[a-zA-Z0-9_-]+$ && ${CLIENT_EXISTS} == '0' && ${#CLIENT_NAME} -lt 16 ]]; do
		read -rp "Имя клиента: " -e CLIENT_NAME
		CLIENT_EXISTS=$(grep -c -E "^### Client ${CLIENT_NAME}\$" "/etc/wireguard/${SERVER_WG_NIC}.conf")

		if [[ ${CLIENT_EXISTS} != 0 ]]; then
			echo ""
			echo -e "${ORANGE}Клиент с указанным именем уже создан, пожалуйста, выберите другое имя.${NC}"
			echo ""
		fi
	done

	for DOT_IP in {2..254}; do
		DOT_EXISTS=$(grep -c "${SERVER_WG_IPV4::-1}${DOT_IP}" "/etc/wireguard/${SERVER_WG_NIC}.conf")
		if [[ ${DOT_EXISTS} == '0' ]]; then
			break
		fi
	done

	if [[ ${DOT_EXISTS} == '1' ]]; then
		echo ""
		echo "Настроенная подсеть поддерживает только 253 клиента."
		exit 1
	fi

	BASE_IP=$(echo "$SERVER_WG_IPV4" | awk -F '.' '{ print $1"."$2"."$3 }')
	until [[ ${IPV4_EXISTS} == '0' ]]; do
		read -rp "IPv4 клиента WireGuard: ${BASE_IP}." -e -i "${DOT_IP}" DOT_IP
		CLIENT_WG_IPV4="${BASE_IP}.${DOT_IP}"
		IPV4_EXISTS=$(grep -c "$CLIENT_WG_IPV4/32" "/etc/wireguard/${SERVER_WG_NIC}.conf")

		if [[ ${IPV4_EXISTS} != 0 ]]; then
			echo ""
			echo -e "${ORANGE}Клиент с указанным IPv4 уже создан, пожалуйста, выберите другой IPv4.${NC}"
			echo ""
		fi
	done

	# Генерация пары ключей для клиента
	CLIENT_PRIV_KEY=$(wg genkey)
	CLIENT_PUB_KEY=$(echo "${CLIENT_PRIV_KEY}" | wg pubkey)
	CLIENT_PRE_SHARED_KEY=$(wg genpsk)

	HOME_DIR=$(getHomeDirForClient "${CLIENT_NAME}")

	# Создание файла клиента и добавление сервера в качестве пира
	echo "[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${CLIENT_WG_IPV4}/32
DNS = ${CLIENT_DNS_1},${CLIENT_DNS_2}

[Peer]
PublicKey = ${SERVER_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
Endpoint = ${SERVER_PUB_IP}:${SERVER_PORT}
AllowedIPs = ${ALLOWED_IPS}" >"${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"

	# Добавление клиента в качестве пира к серверу
	echo -e "\n### Client ${CLIENT_NAME}
[Peer]
PublicKey = ${CLIENT_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
AllowedIPs = ${CLIENT_WG_IPV4}/32" >>"/etc/wireguard/${SERVER_WG_NIC}.conf"

	wg syncconf "${SERVER_WG_NIC}" <(wg-quick strip "${SERVER_WG_NIC}")

	# Генерация QR-кода, если установлен qrencode
	if command -v qrencode &>/dev/null; then
		echo -e "${GREEN}\nВот конфигурация вашего клиента в виде QR-кода:\n${NC}"
		qrencode -t ansiutf8 -l L <"${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"
		echo ""
	fi

	echo -e "${GREEN}Файл конфигурации вашего клиента находится в ${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf${NC}"
}

function listClients() {
	NUMBER_OF_CLIENTS=$(grep -c -E "^### Client" "/etc/wireguard/${SERVER_WG_NIC}.conf")
	if [[ ${NUMBER_OF_CLIENTS} -eq 0 ]]; then
		echo ""
		echo "У вас нет существующих клиентов!"
		exit 1
	fi

	grep -E "^### Client" "/etc/wireguard/${SERVER_WG_NIC}.conf" | cut -d ' ' -f 3 | nl -s ') '
}

function revokeClient() {
	NUMBER_OF_CLIENTS=$(grep -c -E "^### Client" "/etc/wireguard/${SERVER_WG_NIC}.conf")
	if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
		echo ""
		echo "У вас нет существующих клиентов!"
		exit 1
	fi

	echo ""
	echo "Выберите существующего клиента, которого вы хотите отозвать"
	grep -E "^### Client" "/etc/wireguard/${SERVER_WG_NIC}.conf" | cut -d ' ' -f 3 | nl -s ') '
	until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
		if [[ ${CLIENT_NUMBER} == '1' ]]; then
			read -rp "Выберите одного клиента [1]: " CLIENT_NUMBER
		else
			read -rp "Выберите одного клиента [1-${NUMBER_OF_CLIENTS}]: " CLIENT_NUMBER
		fi
	done

	# соответствие выбранного номера имени клиента
	CLIENT_NAME=$(grep -E "^### Client" "/etc/wireguard/${SERVER_WG_NIC}.conf" | cut -d ' ' -f 3 | sed -n "${CLIENT_NUMBER}"p)

	# удаление блока [Peer], соответствующего $CLIENT_NAME
	sed -i "/^### Client ${CLIENT_NAME}\$/,/^$/d" "/etc/wireguard/${SERVER_WG_NIC}.conf"

	# удаление созданного файла клиента
	HOME_DIR=$(getHomeDirForClient "${CLIENT_NAME}")
	rm -f "${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"

	# перезапуск wireguard для применения изменений
	wg syncconf "${SERVER_WG_NIC}" <(wg-quick strip "${SERVER_WG_NIC}")
}

function uninstallWg() {
	echo ""
	echo -e "\n${RED}ВНИМАНИЕ: Это удалит WireGuard и все файлы конфигурации!${NC}"
	echo -e "${ORANGE}Пожалуйста, сделайте резервную копию каталога /etc/wireguard, если вы хотите сохранить файлы конфигурации.\n${NC}"
	read -rp "Вы действительно хотите удалить WireGuard? [y/n]: " -e REMOVE
	REMOVE=${REMOVE:-n}
	if [[ $REMOVE == 'y' ]]; then
		checkOS

		if [[ ${OS} == 'alpine' ]]; then
			rc-service "wg-quick.${SERVER_WG_NIC}" stop
			rc-update del "wg-quick.${SERVER_WG_NIC}"
			unlink "/etc/init.d/wg-quick.${SERVER_WG_NIC}"
			rc-update del sysctl
		else
			systemctl stop "wg-quick@${SERVER_WG_NIC}"
			systemctl disable "wg-quick@${SERVER_WG_NIC}"
		fi

		if [[ ${OS} == 'ubuntu' ]]; then
			apt-get remove -y wireguard wireguard-tools qrencode
		elif [[ ${OS} == 'debian' ]]; then
			apt-get remove -y wireguard wireguard-tools qrencode
		elif [[ ${OS} == 'fedora' ]]; then
			dnf remove -y --noautoremove wireguard-tools qrencode
			if [[ ${VERSION_ID} -lt 32 ]]; then
				dnf remove -y --noautoremove wireguard-dkms
				dnf copr disable -y jdoss/wireguard
			fi
		elif [[ ${OS} == 'centos' ]] || [[ ${OS} == 'almalinux' ]] || [[ ${OS} == 'rocky' ]]; then
			yum remove -y --noautoremove wireguard-tools
			if [[ ${VERSION_ID} == 8* ]]; then
				yum remove --noautoremove kmod-wireguard qrencode
			fi
		elif [[ ${OS} == 'oracle' ]]; then
			yum remove --noautoremove wireguard-tools qrencode
		elif [[ ${OS} == 'arch' ]]; then
			pacman -Rs --noconfirm wireguard-tools qrencode
		elif [[ ${OS} == 'alpine' ]]; then
			(cd qrencode-4.1.1 || exit && make uninstall)
			rm -rf qrencode-* || exit
			apk del wireguard-tools build-base libpng-dev
		fi

		rm -rf /etc/wireguard
		rm -f /etc/sysctl.d/wg.conf

		if [[ ${OS} == 'alpine' ]]; then
			rc-service --quiet "wg-quick.${SERVER_WG_NIC}" status &>/dev/null
		else
			# Перезагрузка sysctl
			sysctl --system

			# Проверка, запущен ли WireGuard
			systemctl is-active --quiet "wg-quick@${SERVER_WG_NIC}"
		fi
		WG_RUNNING=$?

		if [[ ${WG_RUNNING} -eq 0 ]]; then
			echo "WireGuard не удалось удалить корректно."
			exit 1
		else
			echo "WireGuard успешно удален."
			exit 0
		fi
	else
		echo ""
		echo "Удаление отменено!"
	fi
}

function manageMenu() {
	echo "Добро пожаловать в установщик WireGuard (только IPv4)!"
	echo ""
	echo "Похоже, WireGuard уже установлен."
	echo ""
	echo "Что вы хотите сделать?"
	echo "   1) Добавить нового пользователя"
	echo "   2) Список всех пользователей"
	echo "   3) Отозвать существующего пользователя"
	echo "   4) Удалить WireGuard"
	echo "   5) Выход"
	until [[ ${MENU_OPTION} =~ ^[1-5]$ ]]; do
		read -rp "Выберите опцию [1-5]: " MENU_OPTION
	done
	case "${MENU_OPTION}" in
	1)
		newClient
		;;
	2)
		listClients
		;;
	3)
		revokeClient
		;;
	4)
		uninstallWg
		;;
	5)
		exit 0
		;;
	esac
}

# Проверка root, виртуализации, ОС...
initialCheck

# Проверка, установлен ли WireGuard и загрузка параметров
if [[ -e /etc/wireguard/params ]]; then
	source /etc/wireguard/params
	manageMenu
else
	installWireGuard
fi
