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

# 1. Remove non-default packages while preserving desktop environment
log_action "Removing non-default packages while preserving desktop environment..."

# For Debian/Ubuntu based systems
if command -v apt-get &> /dev/null; then
    # Backup current package list
    apt-get update
    apt-mark showmanual > "$backup_dir/manually_installed_packages.txt"
    dpkg --get-selections > "$backup_dir/package_selections.txt"
    
    # Detect desktop environment to preserve
    desktop_env=""
    if dpkg -l | grep -q ubuntu-desktop; then
        desktop_env="ubuntu-desktop"
    elif dpkg -l | grep -q kubuntu-desktop; then
        desktop_env="kubuntu-desktop"
    elif dpkg -l | grep -q xubuntu-desktop; then
        desktop_env="xubuntu-desktop"
    elif dpkg -l | grep -q lubuntu-desktop; then
        desktop_env="lubuntu-desktop"
    elif dpkg -l | grep -q ubuntu-gnome-desktop; then
        desktop_env="ubuntu-gnome-desktop"
    fi
    
    log_action "Detected desktop environment: ${desktop_env:-none}"
    
    if [ -n "$desktop_env" ]; then
        # Make sure the desktop environment is marked as manually installed
        apt-mark manual $desktop_env
        # Also preserve critical X11 and display manager packages
        apt-mark manual xorg lightdm gdm3 gnome-shell firefox ubuntu-session gnome-session
    fi
    
    # Remove only certain categories of packages
    # This approach is less aggressive than the previous one
    log_action "Removing games, extra media players, and non-essential applications..."
    apt-get -y purge libreoffice* thunderbird* gimp* transmission* simple-scan* rhythmbox* \
                     gnome-mahjongg gnome-mines gnome-sudoku aisleriot \
                     cheese* shotwell* remmina* totem* brasero* sound-juicer* \
                     deja-dup* timeshift* synaptic* 
    
    # Remove user-installed packages (those not in the original installation)
    log_action "Removing user-installed packages..."
    if [ -f /var/log/installer/initial-status.gz ]; then
        # Create a list of original packages
        zcat /var/log/installer/initial-status.gz | grep "^Package: " | cut -d" " -f2 > "$backup_dir/original_packages.txt"
        
        # Get current packages
        dpkg --get-selections | grep -v deinstall | cut -f1 > "$backup_dir/current_packages.txt"
        
        # Find packages that were installed after the initial system setup
        # but exclude critical packages
        grep -v -f "$backup_dir/original_packages.txt" "$backup_dir/current_packages.txt" | \
        grep -v -E "($desktop_env|xorg|gdm3|lightdm|gnome-shell|ubuntu-session|gnome-session|network-manager|ubuntu-minimal|ubuntu-standard)" > "$backup_dir/to_remove.txt"
        
        # Remove these packages if the list is not empty
        if [ -s "$backup_dir/to_remove.txt" ]; then
            log_action "Removing $(wc -l < "$backup_dir/to_remove.txt") user-installed packages"
            xargs apt-get -y purge < "$backup_dir/to_remove.txt" || true
        fi
    else
        log_action "Cannot determine original package set; skipping removal of user-installed packages"
    fi
    
    # Remove orphaned packages
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

# 5. Clean up manually installed software
log_action "Cleaning up manually installed software..."

# Check common locations for manually installed software
common_install_dirs=(
    "/usr/local/bin"
    "/usr/local/sbin"
    "/usr/local/games"
    "/usr/local/lib"
    "/opt"
    "/root/.local/bin"
)

# Backup and clean manually installed locations
for dir in "${common_install_dirs[@]}"; do
    if [ -d "$dir" ]; then
        log_action "Processing directory: $dir"
        
        # Create backup
        if [ "$(ls -A $dir 2>/dev/null)" ]; then
            mkdir -p "$backup_dir$dir"
            cp -a "$dir"/* "$backup_dir$dir/" 2>/dev/null || true
            
            # For /opt and /usr/local/lib, be more selective
            if [[ "$dir" == "/opt" || "$dir" == "/usr/local/lib" ]]; then
                # List directories for reference but don't delete essential ones
                find "$dir" -mindepth 1 -maxdepth 1 -type d | sort > "$backup_dir/manual_installs_$(basename $dir).txt"
                log_action "Directories in $dir were backed up but preserved for system stability"
            else
                # For other directories, remove non-essential files
                # Save any system startup scripts
                find "$dir" -type f -not -name "*.service" -not -name "*.timer" > "$backup_dir/removed_from_$(basename $dir).txt"
                find "$dir" -type f -not -name "*.service" -not -name "*.timer" -delete
            fi
        fi
    fi
done

# Clean up flatpak applications if flatpak is installed
if command -v flatpak &> /dev/null; then
    log_action "Backing up and removing Flatpak applications..."
    flatpak list --app > "$backup_dir/flatpak_applications.txt"
    flatpak uninstall --all -y || true
fi

# Clean up snap applications if snap is installed
if command -v snap &> /dev/null; then
    log_action "Backing up and removing non-essential Snap applications..."
    snap list > "$backup_dir/snap_applications.txt"
    
    # Get list of snaps and exclude core snaps
    for snap in $(snap list | grep -v -E '^(core|snapd|bare|base|gtk-common-themes)' | awk '{print $1}'); do
        log_action "Removing snap: $snap"
        snap remove --purge "$snap" || true
    done
fi

# Remove AppImage files
log_action "Looking for and removing AppImage files..."
# Search in common locations for AppImage files
find /home -name "*.AppImage" -type f > "$backup_dir/appimage_files.txt"
if [ -s "$backup_dir/appimage_files.txt" ]; then
    cat "$backup_dir/appimage_files.txt" | xargs rm -f
fi

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