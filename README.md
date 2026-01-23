# Castit OS

**Castit OS** is a specialized, lightweight Digital Signage Operating System built on [NixOS](https://nixos.org/). It is designed to turn x86_64 hardware (Intel/AMD) into a reliable, kiosk-mode digital signage player that boots directly into the Castit web player.

## Features

-   **Kiosk Mode**: Boots directly into `chromium` in kiosk mode, pointing to the Castit player URL.
-   **Automated Installation**: Includes a custom `auto-install` script optimized for low-RAM devices.
-   **Remote Management**: Pre-configured with **Tailscale** for secure remote access and **OpenSSH**.
-   **Auto-Updates**: Automatically pulls the latest configuration from the GitHub repository and rebuilds the system on a timer.
-   **Silent Boot**: Custom Plymouth theme ("logo.png") for a professional, branded boot experience.
-   **Resilience**: Configured with swap and specific boot parameters to ensure stability on constrained hardware.

## Prerequisites

-   **Nix with Flakes**: Ensure you have Nix installed with the `nix-command` and `flakes` experimental features enabled. You can enable them by adding the following to your `~/.config/nix/nix.conf`:
    ```text
    experimental-features = nix-command flakes
    ```
-   **Architecture**: This configuration is designed for `x86_64-linux` hardware.

## Installation

### 1. Create the Installer

The project defines an `installer` output in `flake.nix` which builds a bootable ISO image containing the automated installation script. We use a **Minimal Installer** base to ensure builds are fast and the image is small.

To build the ISO:

```bash
nix build .#installer --impure
```

The resulting ISO will be linked in the `result` symlink in the current directory. This is now a **Zero-Touch Installer**.

#### Flash to USB

You can use several methods to burn this ISO to a USB drive on Linux:

**Method A: Fast Flashing (`bmaptool`) - EXPERT SHORTCUT**
1. Install `bmaptool` (e.g., `sudo apt install bmap-tools` or `nix-shell -p bmap-tools`).
2. Run (replace `/dev/sdX` with your device):
   ```bash
   sudo bmaptool copy result/iso/castit-*.iso /dev/sdX
   ```
   *Why it's fast:* It skips writing empty blocks, often cutting flash time in half.

**Method B: Command Line (`dd`) - Standard**
1. Insert your USB drive.
2. Identify the device path (e.g., `/dev/sdX`) using `lsblk`.
3. Run the following command (replace `/dev/sdX` with your actual device):
   ```bash
   sudo dd if=result/iso/castit-*.iso of=/dev/sdX bs=4M status=progress conv=fsync
   ```

**Method B: GUI - BalenaEtcher (Similar to Rufus)**
If you prefer a Windows-like GUI experience:
1. Download [BalenaEtcher](https://www.balena.io/etcher/).
2. Select the `castit-*.iso` from the `result/iso/` folder.
3. Select your USB drive and click **Flash**.

**Method C: Ventoy (Experimental but powerful)**
If you use [Ventoy](https://www.ventoy.net/), simply copy the `castit-*.iso` file from `result/iso/` onto your Ventoy USB stick.

#### Verify the Flash

After the `dd` command finishes, you can verify the USB partitions by running:
```bash
lsblk /dev/sdX
```
You should see at least two partitions (one for the main OS and one for the EFI boot). On many Linux systems, the main partition will automatically mount as "castit-os".

For a detailed step-by-step guide on the flashing process, see [flashing-walkthrough.md](file:///home/zri/Projects/castit-os/docs/flashing-walkthrough.md).

### 2. Install on Device

1.  Boot the target device from the USB drive.
2.  **Zero-Touch Automation**: The system will automatically skip the bootloader menu and start the `auto-install` script.
3.  **Safety Countdown**: A 20-second countdown will appear. To cancel the automatic install and enter a manual shell, press any key.
4.  If no key is pressed, the script will:
    -   Partition the internal drive (`/dev/mmcblk0` by default - **verify your drive identifier!**).
    -   Format partitions and set up Swap.
    -   Generate a hardware configuration.
    -   Install the `intel-player` configuration with a **hidden bootloader menu**.
    -   Power off the device upon success.

> **Warning**: The `auto-install` script is currently hardcoded for `/dev/mmcblk0`. If you are installing on a SATA SSD or NVMe drive, you may need to modify the script in `flake.nix` to target `/dev/sda` or `/dev/nvme0n1`.

## Architecture

The project is structured as a Nix Flake with two main configurations:

### `intel-player`
The target configuration for the signage player.
-   **File**: `configuration.nix`
-   **Bootloader**: systemd-boot
-   **User**: `kiosk` (auto-login)
-   **Services**: Pipewire, Cage (Wayland compositor), Chromium, Tailscale, Update Service.

### `installer`
The installation medium configuration.
-   **File**: Defined inline in `flake.nix`.
-   **Features**: Includes the `auto-install` script and embeds the configuration files (`flake.nix`, `configuration.nix`, `logo.png`) directly into the ISO so no internet is required to fetch them during the initial install.

## Remote Access & Updates

-   **Tailscale**: The system attempts to auto-join a Tailscale network if a key is provided in `/boot/ts-authkey` or if pre-authenticated.
-   **Updates**: A systemd timer (`update-signage`) runs every hour (and 10m after boot) to check this repository for changes. If changes are found, it pulls them and runs `nixos-rebuild switch`.

## Efficient Development Workflow

You don't need to rebuild the ISO every time you change the configuration.

1.  **Install Once**: Build the ISO and install it on the device one time.
2.  **Push to Update**: For all future changes (updating the URL, changing kiosk flags, adding packages):
    -   Commit and push your changes to the `live` branch of this repository.
    -   The devices will automatically detect the changes, pull them, and apply them within an hour.
    -   **Manual Trigger**: If you want to apply changes immediately, SSH into the device and run: `sudo systemctl start update-signage.service`.

## Customization

-   **URL**: Change `Castit-url` in `configuration.nix` to point to a different player URL.
-   **Logo**: Replace `logo.png` to change the boot splash screen.
- [Remote Management Guide](docs/remote-management.md)
