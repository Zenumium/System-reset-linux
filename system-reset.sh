#!/bin/bash

# Linux System Reset Script
# This script resets a Linux system to a near-default state without reinstalling the OS
# IMPORTANT: Run this script as root (sudo)
# WARNING: This will delete user data and reset configurations!

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (use sudo)."
    exit 1
fi

# Display warning and confirmation
echo "WARNING: This script will reset your system to a near-default state."
echo "All user data, installed applications, and configurations will be removed."
echo "The OS itself will remain installed."
echo ""
echo "This operation CANNOT be undone!"
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
echo "This may take some time. Please do not interrupt the process."

# Function to log actions
log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> /var/log/system-reset.log
    echo "$1"
}

# Create backup directory for important system files
backup_dir="/root/system-reset-backup-$(date '+%Y%m%d%H%M%S')"
mkdir -p "$backup_dir"
log_action "Created backup directory at $backup_dir"

# Backup important system files
log_action "Backing up important system files..."
cp /etc/fstab "$backup_dir"
cp /etc/hostname "$backup_dir"
cp /etc/hosts "$backup_dir"
cp /etc/network/interfaces "$backup_dir" 2>/dev/null || cp -r /etc/netplan "$backup_dir" 2>/dev/null

# Get original distro package list (if available)
if [ -f /var/log/installer/initial-status.gz ]; then
    cp /var/log/installer/initial-status.gz "$backup_dir"
    log_action "Backed up initial package status"
fi

# 1. Remove all non-default packages (distro-specific approaches)
log_action "Removing non-default packages..."

# For Debian/Ubuntu based systems
if command -v apt-get &> /dev/null; then
    # Keep only essential packages
    apt-get update
    apt-mark showmanual > "$backup_dir/manually_installed_packages.txt"
    
    # Option 1: Keep only essential packages
    apt-get -y install aptitude
    aptitude -y markauto '~i!~M!~E!~prequired!~pimportant'
    apt-get -y autoremove --purge
    
    # Clean package cache
    apt-get clean
    apt-get autoclean

# For Red Hat/Fedora based systems
elif command -v dnf &> /dev/null; then
    # Save list of user-installed packages
    dnf repoquery --userinstalled > "$backup_dir/user_installed_packages.txt"
    
    # Reset to a minimal installation
    # This keeps @core and @minimal groups
    dnf -y group install core minimal
    dnf -y remove $(dnf repoquery --userinstalled | grep -v "$(dnf -y group info core minimal | grep -A 999 "Mandatory Packages:" | grep -B 999 "Optional Packages:" | grep -v "Mandatory Packages:" | grep -v "Optional Packages:" | tr '\n' ' ')")
    
    # Clean package cache
    dnf clean all

# For Arch based systems
elif command -v pacman &> /dev/null; then
    # Save current package list
    pacman -Qqe > "$backup_dir/explicitly_installed_packages.txt"
    pacman -Qqn > "$backup_dir/native_packages.txt"
    
    # Remove all but base packages
    pacman -Rns $(pacman -Qqe | grep -v "$(pacman -Qgq base base-devel | tr '\n' '|' | sed 's/|$//')")
    
    # Clean package cache
    pacman -Scc --noconfirm
fi

# 2. Reset user accounts (keep the primary user but reset their settings)
log_action "Resetting user accounts..."

# Get all non-system users
for user in $(awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd); do
    # Skip root
    if [ "$user" != "root" ]; then
        user_home=$(eval echo ~$user)
        
        log_action "Resetting user: $user (home: $user_home)"
        
        # Backup .bashrc and other important files
        mkdir -p "$backup_dir/user_$user"
        [ -f $user_home/.bashrc ] && cp $user_home/.bashrc "$backup_dir/user_$user/"
        [ -f $user_home/.profile ] && cp $user_home/.profile "$backup_dir/user_$user/"
        [ -f $user_home/.ssh/authorized_keys ] && mkdir -p "$backup_dir/user_$user/.ssh" && cp $user_home/.ssh/authorized_keys "$backup_dir/user_$user/.ssh/"
        
        # Remove user data except .ssh authorized keys
        find $user_home -mindepth 1 -not -path "$user_home/.ssh" -not -path "$user_home/.ssh/authorized_keys" -delete || true
        mkdir -p $user_home/.ssh
        chmod 700 $user_home/.ssh
        
        # Copy default config files
        cp -r /etc/skel/. $user_home/
        
        # Fix ownership
        chown -R $user:$user $user_home
    fi
done

# 3. Reset system configurations
log_action "Resetting system configurations..."

# Reset hostname (optional, comment out if you want to keep your hostname)
echo "linux" > /etc/hostname
echo "127.0.0.1 localhost" > /etc/hosts
echo "127.0.1.1 linux" >> /etc/hosts

# Reset network settings (distribution specific)
if [ -d /etc/netplan ]; then
    # For Ubuntu with netplan
    echo "# Default netplan config
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true" > /etc/netplan/01-netcfg.yaml
    netplan apply
elif [ -f /etc/network/interfaces ]; then
    # For Debian with ifupdown
    echo "# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
allow-hotplug eth0
iface eth0 inet dhcp" > /etc/network/interfaces
    systemctl restart networking || ifdown -a && ifup -a
fi

# Reset firewall rules
if command -v ufw &> /dev/null; then
    ufw reset
    ufw enable
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --zone=public --reset-to-defaults
    firewall-cmd --reload
fi

# Clear logs
log_action "Clearing system logs..."
find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;
find /var/log -type f -name "*.log.*" -delete
journalctl --vacuum-time=1s >/dev/null 2>&1 || true

# Clear temporary files
log_action "Clearing temporary files..."
rm -rf /tmp/*
rm -rf /var/tmp/*

# Reset crontabs
log_action "Resetting crontabs..."
for user in $(cut -f1 -d: /etc/passwd); do
    crontab -r -u $user >/dev/null 2>&1 || true
done

# 4. Clear system caches
log_action "Clearing system caches..."
sync
echo 3 > /proc/sys/vm/drop_caches

# Optional: Reset GRUB to default (be careful with this)
if command -v update-grub &> /dev/null; then
    log_action "Resetting GRUB configuration..."
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/' /etc/default/grub
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub
    update-grub
fi

# Final cleanup and summary
log_action "System reset completed!"
log_action "Backup of important files created at: $backup_dir"
log_action "You should reboot your system now for changes to take effect."

echo ""
echo "============================="
echo "System reset process complete!"
echo "============================="
echo ""
echo "A backup of important system files was created at: $backup_dir"
echo "Please reboot your system now for all changes to take effect."
echo ""

read -p "Would you like to reboot now? (yes/no): " reboot_choice
if [ "$reboot_choice" = "yes" ]; then
    log_action "Rebooting system..."
    reboot
fi
