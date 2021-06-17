#! /bin/bash


if [ $EUID -ne 0 ]; then
    echo "$(basename $0) must be run as root"
    exit 1
fi

#### Wait for conenction or ask the user for configuration ####
whiptail --infobox "Checking connection..." 10 50
sleep 5

while ! ( curl -Is https://gamer-os.github.io/ | head -1 | grep 200 > /dev/null ); do
    whiptail --yesno "No wired connection detected. Please connect this computer \
     to the internet by configuring a new network." 10 50 \
     --yes-button "Configure" \
     --no-button "Exit"

    if [ $? -ne 0 ]; then
         exit 1
    fi

    nmtui-connect
done
#######################################

if ! frzr-bootstrap gamer; then
    exit 1
fi

# Post install steps for system configuration
# Copy over all network configuration from the live session to the system
MOUNT_PATH=/tmp/frzr_root
if [ -d "/etc/NetworkManager/system-connections" ]; then
    mkdir -p -m=700 ${MOUNT_PATH}/etc/NetworkManager/system-connections
    cp  /etc/NetworkManager/system-connections/* \
        ${MOUNT_PATH}/etc/NetworkManager/system-connections/.
fi

export SHOW_UI=1
if ! frzr-deploy gamer-os/gamer-os:stable; then
    echo "Installation failed."
    exit 1
fi

if (whiptail --yesno "Installation complete. Would you like to restart now?" 10 50); then
    reboot
fi
