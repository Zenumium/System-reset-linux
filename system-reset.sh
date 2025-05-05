#!/bin/bash

# Ubuntu/Linux System Reset Script
# This script resets a Linux system to a cleaner state while preserving the desktop environment
# It removes non-essential applications, clears user data, and resets configurations
# IMPORTANT: Run this script as root (sudo)
# WARNING: This will delete user data and reset configurations!

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (use sudo)."
    exit 1
fi

# Display warning and confirmation
echo "This script was created By Projeckt Aqua to help users reset their Linux systems."
echo ""
echo "==================================================="
echo "WARNING: This script will reset your system to a near-default state."
echo "All user data, installed applications, and configurations will be removed."
echo "The OS itself will remain installed."
echo ""
echo "This operation CANNOT be undone!"
echo "==================================================="
read -p "Are you absolutely sure you want to continue? (yes/no): " confirmation

if [ "$confirmation" != "yes" ]; then
    echo "Operation cancelled."
    exit 0
fi

read -p "Enter 'CONFIRM RESET' in all caps to proceed: " final_confirmation

if [ "$final_confirmation" != "CONFIRM RESET" ]; then
    echo "Operation cancelled."
    exit 0
fi

echo "Starting system reset process..."

backup_dir="/root/system-reset-backup-$(date '+%Y%m%d%H%M%S')"
mkdir -p "$backup_dir"
echo "Backup directory created at $backup_dir"

cp /etc/fstab "$backup_dir"
cp /etc/hostname "$backup_dir"
cp /etc/hosts "$backup_dir"
cp -r /etc/netplan "$backup_dir" 2>/dev/null || cp /etc/network/interfaces "$backup_dir" 2>/dev/null

if command -v apt-get &> /dev/null; then
    apt-get update
    apt-mark showmanual > "$backup_dir/manual.txt"
    dpkg --get-selections > "$backup_dir/packages.txt"

    desktop_env=""
    for env in ubuntu-desktop kubuntu-desktop xubuntu-desktop lubuntu-desktop ubuntu-gnome-desktop; do
        if dpkg -l | grep -q $env; then
            desktop_env=$env
            break
        fi
    done

    if [ -n "$desktop_env" ]; then
        apt-mark manual $desktop_env xorg lightdm gdm3 gnome-shell ubuntu-session gnome-session
    fi

    apt-get -y purge libreoffice* gimp* transmission* simple-scan* gnome-mahjongg gnome-mines gnome-sudoku aisleriot shotwell* remmina* totem* brasero* sound-juicer* deja-dup* timeshift* synaptic*

    apt-get -y autoremove --purge
    apt-get clean
fi

for user in $(awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd); do
    user_home=$(eval echo ~$user)
    mkdir -p "$backup_dir/user_$user"
    [ -f $user_home/.bashrc ] && cp $user_home/.bashrc "$backup_dir/user_$user/"
    [ -f $user_home/.profile ] && cp $user_home/.profile "$backup_dir/user_$user/"
    rm -rf $user_home/*
    cp -r /etc/skel/. $user_home/
    chown -R $user:$user $user_home

done

echo "127.0.0.1 localhost" > /etc/hosts
echo "127.0.1.1 linux" >> /etc/hosts

echo "linux" > /etc/hostname

if [ -d /etc/netplan ]; then
    echo "network:\n  version: 2\n  ethernets:\n    eth0:\n      dhcp4: true" > /etc/netplan/01-netcfg.yaml
    netplan apply
fi

if command -v ufw &> /dev/null; then
    ufw reset
    ufw enable
fi

find /var/log -type f -exec truncate -s 0 {} \;
rm -rf /tmp/* /var/tmp/*

# Modified Snap handling to be more robust
if command -v snap &> /dev/null; then
    echo "Listing installed snap packages..."
    snap_list_output=$(snap list 2>&1) # Capture output and errors

    # Check if snap list command was successful
    if echo "$snap_list_output" | grep -q "Name"; then
        echo "Saving list of installed snaps to $backup_dir/snap_list.txt"
        echo "$snap_list_output" > "$backup_dir/snap_list.txt"

        echo "Removing non-essential snap packages..."
        # Use awk to extract snap names, skipping the header
        snap_packages=$(echo "$snap_list_output" | awk 'NR>1 {print $1}')

        if [ -n "$snap_packages" ]; then
            for snap in $snap_packages; do
                # Exclude essential snaps and the snap-store
                if ! [[ "$snap" =~ ^(core|core18|core20|core22|snapd|bare|base|gtk-common-themes|snap-store)$ ]]; then
                    echo "Removing snap: $snap"
                    snap remove --purge "$snap" || true
                fi
            done
        else
            echo "No removable snap packages found."
        fi
    else
        echo "Warning: Failed to list snap packages. Skipping snap removal."
        echo "Details: $snap_list_output"
    fi
else
    echo "Warning: snap command not found. Skipping snap removal."
fi

echo "System reset completed. Backup saved at $backup_dir"
echo "Rebooting is recommended."
read -p "Reboot now? (yes/no): " reboot_choice
if [ "$reboot_choice" = "yes" ]; then
    reboot
fi