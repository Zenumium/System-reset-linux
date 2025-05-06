#!/bin/bash

# Define colors and styles for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
UNDERLINE='\033[4m'
RESET='\033[0m'

# Function to print watermark banner
print_watermark() {
    echo -e "${CYAN}${BOLD}==============================================${RESET}"
    echo -e "${CYAN}${BOLD}              Made by Projeckt Aqua          ${RESET}"
    echo -e "${CYAN}${BOLD}==============================================${RESET}"
    echo ""
}

# Print watermark at the start
print_watermark

# Ubuntu/Linux System Reset Script
# This script resets a Linux system to a cleaner state while strictly preserving essential components.
# It removes non-essential applications, clears user data, and resets configurations.
# IMPORTANT: Run this script as root (sudo)
# WARNING: This will delete user data and reset configurations!

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}This script must be run as root (use sudo).${RESET}"
    exit 1
fi

# Display warning and confirmation
echo -e "${BOLD}This script help users reset their Linux systems.${RESET}"
echo ""
echo -e "${YELLOW}===================================================${RESET}"
echo -e "${RED}${BOLD}WARNING: This script will reset your system to a near-default state.${RESET}"
echo -e "${YELLOW}Make sure to back up any important data before proceeding.${RESET}"
echo -e "${YELLOW}All user data, installed applications, and configurations will be removed.${RESET}"
echo -e "${YELLOW}The OS itself will remain installed.${RESET}"
echo ""
echo -e "${RED}${BOLD}This operation CANNOT be undone!${RESET}"
echo -e "${YELLOW}===================================================${RESET}"
read -p "Are you absolutely sure you want to continue? (yes/no): " confirmation


if [ "$confirmation" != "yes" ]; then
    echo -e "${RED}Operation cancelled.${RESET}"
    exit 0
fi

read -p "Enter 'CONFIRM RESET' in all caps to proceed: " final_confirmation

if [ "$final_confirmation" != "CONFIRM RESET" ]; then
    echo -e "${RED}Operation cancelled.${RESET}"
    exit 0
fi

echo -e "${GREEN}Starting system reset process...${RESET}"
echo -e "${CYAN}This may take some time. Please do not interrupt the process.${RESET}"

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

# 1. Remove non-default packages while strictly preserving essential components
log_action "Removing non-default packages while strictly preserving essential components..."

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

    # Define essential packages that MUST NOT be removed
    essential_packages=(
        "$(echo "$desktop_env" | sed 's/-desktop//')" # Base desktop package (e.g., ubuntu, kubuntu)
        "xorg"
        "lightdm" "gdm3" # Common display managers
        "gnome-shell" "xfce4" "lxqt" # Common desktop shells (ensure relevant one is included)
        "ubuntu-session" "gnome-session" # Session managers
        "network-manager"
        "sudo"
        "apt"
        "dpkg"
        "init" "systemd" # Essential system components
        "linux-image-*" "linux-modules-*" "linux-firmware" # Kernel related
        "base-files" "base-passwd" "bash" "coreutils" # Fundamental utilities
        "snap-store" # Keep Snap Store
        "firefox" "firefox-*" # Keep Firefox 
        # Add any other packages that MUST be preserved here, e.g., "My App"
    )
    essential_pattern=$(IFS='|'; echo "${essential_packages[*]}")
    log_action "Essential packages to preserve: $essential_pattern"

    if [ -n "$desktop_env" ]; then
        # Mark essential packages as manually installed to prevent auto-removal
        apt-mark manual "${essential_packages[@]}"
    fi

    # Remove only certain categories of packages, EXCLUDING essential ones
    log_action "Removing non-essential applications (games, extra media players, etc.)..."
    apt-get -y purge libreoffice* thunderbird* gimp* transmission* simple-scan* rhythmbox* \
                     gnome-mahjongg gnome-mines gnome-sudoku aisleriot \
                     cheese* shotwell* remmina* totem* brasero* sound-juicer* \
                     deja-dup* timeshift* synaptic*
    # Note: Removed 'snap-store*' and 'firefox*' from the purge list above

    # Remove user-installed packages (those not in the original installation), EXCLUDING essential ones
    log_action "Removing user-installed packages (excluding essential ones)..."
    if [ -f /var/log/installer/initial-status.gz ]; then
        # Create a list of original packages
        zcat /var/log/installer/initial-status.gz | grep "^Package: " | cut -d" " -f2 > "$backup_dir/original_packages.txt"

        # Get current packages
        dpkg --get-selections | grep -v deinstall | cut -f1 > "$backup_dir/current_packages.txt"

        # Find packages that were installed after the initial system setup
        # and are NOT in the essential packages list
        grep -v -f "$backup_dir/original_packages.txt" "$backup_dir/current_packages.txt" | \
        grep -v -E "($essential_pattern)" > "$backup_dir/to_remove.txt"

        # Remove these packages if the list is not empty
        if [ -s "$backup_dir/to_remove.txt" ]; then
            log_action "Removing $(wc -l < "$backup_dir/to_remove.txt") user-installed packages (excluding essential ones)"
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

    # Define essential package groups and packages (adjust as needed)
    essential_groups=("core" "minimal")
    essential_packages=(
        # Add individual essential packages here if needed
        "snapd" # Keep Snap-related packages
    )
    essential_patterns=$(echo "${essential_groups[@]}" | sed 's/ /\|/g')

    # Get list of initially installed packages (may require adjustments based on distro)
    initial_packages=$(rpm -qa --queryformat "%{NAME}\n" | sort)
    echo "$initial_packages" > "$backup_dir/initial_packages.txt"

    # Get list of user-installed packages not belonging to essential groups
    user_installed=$(dnf repoquery --userinstalled --exclude "@${essential_patterns}" | sort)
    echo "$user_installed" > "$backup_dir/non_essential_user_installed.txt"

    if [ -s "$backup_dir/non_essential_user_installed.txt" ]; then
        log_action "Removing non-essential user-installed packages..."
        dnf -y remove $(cat "$backup_dir/non_essential_user_installed.txt")
    else
        log_action "No non-essential user-installed packages found."
    fi

    # Clean package cache
    dnf clean all

# For Arch based systems
elif command -v pacman &> /dev/null; then
    # Save current package list
    pacman -Qqe > "$backup_dir/explicitly_installed_packages.txt"
    pacman -Qqn > "$backup_dir/native_packages.txt"

    # Define essential package groups (adjust as needed)
    essential_groups=("base" "base-devel")
    essential_pattern=$(echo "${essential_groups[@]}" | sed 's/ /\|/g')

    # Get list of explicitly installed packages not belonging to essential groups
    to_remove=$(pacman -Qqe | grep -v -E "($(pacman -Qgq "${essential_groups[@]}" | tr '\n' '|' | sed 's/|$//'))")

    if [ -n "$to_remove" ]; then
        log_action "Removing explicitly installed packages (excluding essential groups)..."
        pacman -Rns "$to_remove" --noconfirm
    else
        log_action "No non-essential explicitly installed packages found."
    fi

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

# 5. Clean up manually installed software and development tools
log_action "Cleaning up manually installed software and development tools..."

# Enhanced removal of development tools - specifically target git, nodejs, and flatpak
if command -v apt-get &> /dev/null; then
    log_action "Explicitly removing Git, Node.js, and Flatpak..."
    apt-get -y purge git git-* nodejs node-* npm flatpak || true
fi

if command -v dnf &> /dev/null; then
    log_action "Explicitly removing Git, Node.js, and Flatpak via dnf..."
    dnf -y remove git nodejs npm flatpak || true
fi

if command -v pacman &> /dev/null; then
    log_action "Explicitly removing Git, Node.js, and Flatpak via pacman..."
    pacman -Rns --noconfirm git nodejs npm flatpak || true
fi

# Remove common development tools (unless they're in the essential packages list)
dev_packages_to_remove=(
    "git" "git-*"
    "nodejs" "node-*" "npm"
    "python*-dev" "python*-pip" "python*-venv" "python*-setuptools"
    "ruby" "ruby-dev" "rubygems" "gem"
    "php*" "php*-cli" "php*-common" "composer"
    "gcc" "g++" "make" "build-essential" "cmake" "autoconf" "automake"
    "golang" "golang-go"
    "rust*" "cargo"
    "openjdk*" "maven" "gradle"
    "docker*" "docker.io" "podman" "containerd"
    "yarn" "typescript" "babel"
    "mongodb*" "mysql*" "postgresql*" "redis*"
    "apache2*" "nginx*"
    "flatpak"  # Add flatpak explicitly to the list
)

if command -v apt-get &> /dev/null; then
    log_action "Removing development tools via apt-get..."
    
    # Create a pattern that excludes essential packages
    exclude_pattern=""
    for pkg in "${essential_packages[@]}"; do
        exclude_pattern="$exclude_pattern|$pkg"
    done
    exclude_pattern="${exclude_pattern:1}" # Remove the leading |
    
    # Filter packages to remove against the essential package list
    filtered_packages=()
    for pkg in "${dev_packages_to_remove[@]}"; do
        if ! [[ "$pkg" =~ $exclude_pattern ]]; then
            filtered_packages+=("$pkg")
        fi
    done
    
    # Remove development packages that are not in the essential list
    if [ ${#filtered_packages[@]} -gt 0 ]; then
        log_action "Removing ${#filtered_packages[@]} development packages..."
        apt-get -y purge "${filtered_packages[@]}" || true
        apt-get -y autoremove --purge
    fi
elif command -v dnf &> /dev/null; then
    log_action "Removing development tools via dnf..."
    dnf -y remove git nodejs npm python*-devel python*-pip ruby rubygems golang rust cargo flatpak || true
    dnf -y autoremove
elif command -v pacman &> /dev/null; then
    log_action "Removing development tools via pacman..."
    pacman -Rns --noconfirm git nodejs npm python python-pip ruby go rust flatpak || true
fi

# Remove version managers and language-specific tools
log_action "Removing version managers and language-specific tools..."
version_managers=(
    "/home/*/.nvm"
    "/home/*/.n"
    "/home/*/.pyenv"
    "/home/*/.rbenv"
    "/home/*/.sdkman"
    "/home/*/.rustup"
    "/home/*/.cargo"
    "/home/*/.volta"
    "/home/*/.gvm"
    "/home/*/.jenv"
    "/home/*/.goenv"
    "/home/*/.nodenv"
)

for vm_path in "${version_managers[@]}"; do
    if ls $vm_path &>/dev/null; then
        log_action "Removing version manager: $vm_path"
        rm -rf $vm_path
    fi
done

# Remove language-specific package managers in home directories
log_action "Removing language-specific package managers in home directories..."
pkg_managers=(
    "/home/*/.npm"
    "/home/*/.yarn"
    "/home/*/.pip"
    "/home/*/.gem"
    "/home/*/.composer"
    "/home/*/.bundle"
    "/home/*/.nuget"
    "/home/*/.gradle"
    "/home/*/.m2"
    "/home/*/.sbt"
    "/home/*/.ivy2"
)

for pkg_path in "${pkg_managers[@]}"; do
    if ls $pkg_path &>/dev/null; then
        log_action "Removing package manager: $pkg_path"
        rm -rf $pkg_path
    fi
done

# Clean up global npm packages
if command -v npm &> /dev/null; then
    log_action "Backing up and removing global npm packages..."
    npm ls -g --depth=0 > "$backup_dir/npm_global_packages.txt"
    npm_prefix=$(npm config get prefix)
    if [ -d "$npm_prefix/lib/node_modules" ]; then
        log_action "Removing global npm packages in $npm_prefix/lib/node_modules"
        find "$npm_prefix/lib/node_modules" -mindepth 1 -maxdepth 1 -not -name "npm" -exec rm -rf {} \;
    fi
fi

# Remove Docker images and containers if Docker is installed
if command -v docker &> /dev/null; then
    log_action "Backing up and removing Docker containers and images..."
    docker ps -a > "$backup_dir/docker_containers.txt"
    docker images > "$backup_dir/docker_images.txt"
    
    # Stop and remove all containers
    docker stop $(docker ps -a -q) 2>/dev/null || true
    docker rm $(docker ps -a -q) 2>/dev/null || true
    
    # Remove all images
    docker rmi $(docker images -q) 2>/dev/null || true
    
    # Prune volumes and networks
    docker volume prune -f 2>/dev/null || true
    docker network prune -f 2>/dev/null || true
    docker system prune -a -f 2>/dev/null || true
fi

# Check common locations for manually installed software
common_install_dirs=(
    "/usr/local/bin"
    "/usr/local/sbin"
    "/usr/local/games"
    "/usr/local/lib"
    "/opt"
    "/root/.local/bin"
)

# Specifically look for and remove git, node, npm, and flatpak binaries in common paths
log_action "Looking for manually installed git, node, npm, and flatpak binaries..."
for dir in "/usr/local/bin" "/usr/local/sbin" "/usr/bin" "/usr/sbin" "/bin" "/sbin"; do
    for binary in "git" "node" "npm" "flatpak"; do
        if [ -f "$dir/$binary" ]; then
            log_action "Found $binary in $dir, removing..."
            rm -f "$dir/$binary"
        fi
    done
done

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
                
                # Get list of common development tools binaries to remove
                dev_binaries=("git" "node" "npm" "yarn" "python" "pip" "ruby" "gem" "php" "composer" 
                              "gcc" "g++" "make" "cmake" "go" "cargo" "rustc" "mvn" "gradle" "docker" 
                              "kubectl" "terraform" "ansible" "vagrant" "flatpak")
                
                # Remove development tool binaries
                for binary in "${dev_binaries[@]}"; do
                    if [ -f "$dir/$binary" ]; then
                        log_action "Removing development binary: $dir/$binary"
                        rm -f "$dir/$binary"
                    fi
                done
                
                # Remove remaining non-essential files
                find "$dir" -type f -not -name "*.service" -not -name "*.timer" -delete
            fi
        fi
    fi
done

# Clean up flatpak applications and the flatpak system itself
if command -v flatpak &> /dev/null; then
    log_action "Backing up and removing Flatpak applications and Flatpak system..."
    flatpak list --app > "$backup_dir/flatpak_applications.txt"
    flatpak uninstall --all -y || true
    
    # After uninstalling all flatpak apps, try to remove the flatpak package itself
    if command -v apt-get &> /dev/null; then
        apt-get -y purge flatpak
    elif command -v dnf &> /dev/null; then
        dnf -y remove flatpak
    elif command -v pacman &> /dev/null; then
        pacman -Rns --noconfirm flatpak
    fi
    
    # Remove flatpak data directories
    rm -rf /var/lib/flatpak/* 2>/dev/null || true
    rm -rf ~/.local/share/flatpak/* 2>/dev/null || true
fi

# Clean up snap applications if snap is installed (excluding core and essential snaps)
if command -v snap &> /dev/null; then
    log_action "Backing up and removing non-essential Snap applications (excluding core and snap-store)..."
    snap list > "$backup_dir/snap_applications.txt"

    # Define essential snap packages to keep
    essential_snaps=(
        "core"
        "snapd"
        "bare"
        "base"
        "gtk-common-themes"
        "snap-store"  # Added snap-store to keep it preserved
        "firefox"     # Keep Firefox snap
        "gnome-3-38-2004"  # Dependency for snap-store
        "gnome-42-2204"    # Newer dependency for snap-store
        # Add any other essential snaps here
    )
    essential_snap_pattern=$(IFS='|'; echo "^(${essential_snaps[*]})$")

    # Get list of snaps and exclude essential ones
    for snap in $(snap list | awk '{print $1}' | grep -v -E "$essential_snap_pattern"); do
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
echo "Development tools were removed"
echo "Please reboot your system now for all changes to take effect."
echo ""

read -p "Would you like to reboot now? (yes/no): " reboot_choice
if [ "$reboot_choice" = "yes" ]; then
    log_action "Rebooting system..."
    reboot
fi

# Print watermark at the end
print_watermark