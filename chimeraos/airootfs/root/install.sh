#! /bin/bash

clean_progress() {
        local scale=$1
        local postfix=$2
        local last_value=$scale
        while IFS= read -r line; do
                value=$(( ${line}*${scale}/100 ))
                if [ "$last_value" != "$value" ]; then
                        echo ${value}${postfix}
                        last_value=$value
                fi
        done
}


if [ $EUID -ne 0 ]; then
    echo "$(basename $0) must be run as root"
    exit 1
fi

dmesg --console-level 1

if [ ! -d /sys/firmware/efi/efivars ]; then
    MSG="Установка через BIOS метод загрузки недоступна. Вам необходимо использовать режим UEFI.\n\nХотите перезагрузить компьютер сейчас?"
    if (whiptail --yesno "${MSG}" 10 50); then
        reboot
    fi

    exit 1
fi


# try to set correct date & time -- required to be able to connect to github via https if your hardware clock is set too far into the past
timedatectl set-ntp true


#### Test connection or ask the user for configuration ####

# Waiting a bit because some wifi chips are slow to scan 5GHZ networks and to avoid kernel boot up messages printing over the screen
sleep 10

TARGET="stable"
while ! ( curl --http1.1 -Ls https://github.com | grep '<html' > /dev/null ); do
    whiptail \
     "Интернет-соединения не обнаружено.\n\nПожалуйста, используйте утилиту настройки интернета, для его подключения, за тем выберите \"Выйти\" для выхода из утилиты и продолжения установки." \
     12 50 \
     --yesno \
     --yes-button "Настроить" \
     --no-button "Выйти"

    if [ $? -ne 0 ]; then
         exit 1
    fi

    nmtui-connect
done
#######################################

MOUNT_PATH=/tmp/frzr_root

if ! frzr-bootstrap gamer; then
    whiptail --msgbox "System bootstrap step failed." 10 50
    exit 1
fi

#### Post install steps for system configuration
# Copy over all network configuration from the live session to the system
SYS_CONN_DIR="/etc/NetworkManager/system-connections"
if [ -d ${SYS_CONN_DIR} ] && [ -n "$(ls -A ${SYS_CONN_DIR})" ]; then
    mkdir -p -m=700 ${MOUNT_PATH}${SYS_CONN_DIR}
    cp  ${SYS_CONN_DIR}/* \
        ${MOUNT_PATH}${SYS_CONN_DIR}/.
fi

# Grab the steam bootstrap for first boot

URL="https://steamdeck-packages.steamos.cloud/archlinux-mirror/jupiter-main/os/x86_64/steam-jupiter-stable-1.0.0.78-1.2-x86_64.pkg.tar.zst"
TMP_PKG="/tmp/package.pkg.tar.zst"
TMP_FILE="/tmp/bootstraplinux_ubuntu12_32.tar.xz"
DESTINATION="/tmp/frzr_root/etc/first-boot/"
if [[ ! -d "$DESTINATION" ]]; then
      mkdir -p /tmp/frzr_root/etc/first-boot
fi

curl --http1.1 -# -L -o "${TMP_PKG}" -C - "${URL}" 2>&1 | \
stdbuf -oL tr '\r' '\n' | grep --line-buffered -oP '[0-9]*+(?=.[0-9])' | clean_progress 100 | \
whiptail --gauge "Загрузка Steam" 10 50 0

tar -I zstd -xvf "$TMP_PKG" usr/lib/steam/bootstraplinux_ubuntu12_32.tar.xz -O > "$TMP_FILE"
mv "$TMP_FILE" "$DESTINATION"
rm "$TMP_PKG"

MENU_SELECT=$(whiptail --menu "Варианты установки" 25 75 10 \
  "Стандартная:" "Установка с стандартными настройками" \
  "Продвинутая:" "Установка с расширенными настройками" \
   3>&1 1>&2 2>&3)

if [ "$MENU_SELECT" = "Продвинутая:" ]; then
  OPTIONS=$(whiptail --separate-output --checklist "Выберите настройки" 10 55 4 \
    "Использовать Firmware Overrides" "DSDT/EDID" OFF \
    "Нестабильные сборки" "" OFF 3>&1 1>&2 2>&3)

  if echo "$OPTIONS" | grep -q "Использовать Firmware Overrides"; then
    echo "Enabling firmware overrides..."
    if [[ ! -d "/tmp/frzr_root/etc/device-quirks/" ]]; then
      mkdir -p "/tmp/frzr_root/etc/device-quirks"
      # Create device-quirks default config
      cat >"/tmp/frzr_root/etc/device-quirks/device-quirks.conf" <<EOL
export USE_FIRMWARE_OVERRIDES=1
export USB_WAKE_ENABLED=1
EOL
      # Create dsdt_override.log with default values
      cat >"/tmp/frzr_root/etc/device-quirks/dsdt_override.log" <<EOL
LAST_DSDT=None
LAST_BIOS_DATE=None
LAST_BIOS_RELEASE=None
LAST_BIOS_VENDOR=None
LAST_BIOS_VERSION=None
EOL
    fi
  fi

  if echo "$OPTIONS" | grep -q "Нестабильные сборки"; then
    TARGET="unstable"
  fi
fi


export SHOW_UI=1

if ( ls -1 /dev/disk/by-label | grep -q FRZR_UPDATE ); then

CHOICE=$(whiptail --menu "How would you like to install ChimeraOS?" 18 50 10 \
  "local" "Use local media for installation." \
  "online" "Fetch the latest stable image." \
   3>&1 1>&2 2>&3)
fi

if [ "${CHOICE}" == "local" ]; then
    export local_install=true
    frzr-deploy
    RESULT=$?
else
    frzr-deploy gru2007/chimera-cyberium:${TARGET}
    RESULT=$?
fi

MSG="Installation failed."
if [ "${RESULT}" == "0" ]; then
    MSG="Установка успешно выполнена."
elif [ "${RESULT}" == "29" ]; then
    MSG="GitHub API rate limit error encountered. Please retry installation later."
fi

if (whiptail --yesno "${MSG}\n\nХотите перезагрузить компьютер сейчас?" 10 50); then
    reboot
fi

exit ${RESULT}
