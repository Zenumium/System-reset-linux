# System Reset Script

This is a Linux system reset script created by Projeckt Aqua. The script is designed to reset a Linux system to a cleaner, near-default state while strictly preserving essential system components.

## What the Script Does

- Checks if the script is run as root (sudo) and exits if not.
- Displays warnings and requires user confirmation before proceeding.
- Creates a backup directory for important system files.
- Backs up critical configuration files such as `/etc/fstab`, `/etc/hostname`, `/etc/hosts`, and network settings.
- Removes non-default and non-essential packages while preserving essential system and desktop environment packages.
- Resets user accounts by clearing user data but preserving SSH authorized keys and default configuration files.
- Resets system configurations including hostname, network settings, and firewall rules.
- Clears system logs, temporary files, and system caches.
- Removes development tools, language-specific package managers, and version managers.
- Cleans up Docker containers, images, and volumes if Docker is installed.
- Optionally resets GRUB configuration to default.
- Provides a summary and prompts the user to reboot the system.

## Visual Enhancements

- The script outputs colored and formatted messages for better readability in the terminal.

## Usage

Run the script as root (using `sudo`):

```bash
sudo ./system-reset.sh
```

If the script does not run, try making it executable with:

```bash
chmod +x system-reset.sh
```

Then, run it with `sudo`.


Follow the on-screen prompts carefully. The script will ask for confirmation before proceeding with the reset.

**Warning:** This script will delete user data, installed applications, and reset configurations. The operation cannot be undone.

## Disclaimer

Use this script at your own risk. It is recommended to back up important data before running the script.

## Author

Made by Projeckt Aqua
