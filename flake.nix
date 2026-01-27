{
  description = "Castit Digital Signage OS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11"; 
  };

  outputs = { self, nixpkgs, ... }: {
    packages.x86_64-linux = {
      installer = self.nixosConfigurations.installer.config.system.build.isoImage;
      default = self.packages.x86_64-linux.installer;
    };

    nixosConfigurations = {
      
      # ==========================================
      # 1. THE PLAYER (Target System on SSD)
      # ==========================================
      intel-player = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          /etc/nixos/hardware-configuration.nix # Absolute path - always read from device
          ({ pkgs, lib, ... }: {
            boot.loader.systemd-boot.enable = true;
            boot.loader.systemd-boot.editor = false;
            boot.loader.timeout = lib.mkForce 0;
            boot.loader.efi.canTouchEfiVariables = true;
          })
        ];
      };

      # ==========================================
      # 2. THE INSTALLER ISO (USB Stick)
      # ==========================================
      installer = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ({ pkgs, lib, ... }: {
            system.nixos.distroName = "Castit OS";
            system.nixos.distroId = "castit";

            # Hide the bootloader menu entirely
            boot.loader.timeout = lib.mkForce 0;
            boot.loader.systemd-boot.editor = false;
            
            # Embed the config files into the ISO so we don't need Git
            environment.etc."nixos-config/flake.nix".source = ./flake.nix;
            environment.etc."nixos-config/configuration.nix".source = ./configuration.nix;
            environment.etc."nixos-config/logo.png".source = ./logo.png;

            # Added compatibility modules for Stage 1 boot
            boot.initrd.availableKernelModules = [ "uas" "xhci_pci" "usb_storage" "vmd" "nvme" "ahci" "sd_mod" ];

            # The "Low Memory" Automation Script
            environment.systemPackages = [
              (pkgs.writeShellScriptBin "auto-install" ''
                set -e
                echo "--- STARTING CASTIT OS AUTOMATED INSTALL (LOW RAM MODE) ---"                
                echo "!!! WARNING: THIS WILL WIPE /dev/mmcblk0 !!!"
                echo -e "\nProceeding with installation..."

                # 1. Manual Partitioning (Uses less RAM than Disko)
                echo ">>> [1/5] Partitioning /dev/mmcblk0..."
                sudo parted -s /dev/mmcblk0 mklabel gpt
                sudo parted -s /dev/mmcblk0 mkpart ESP fat32 1MiB 512MiB
                sudo parted -s /dev/mmcblk0 set 1 esp on
                sudo parted -s /dev/mmcblk0 mkpart primary ext4 512MiB 100%
                
                # 2. Format
                echo ">>> [2/5] Formatting..."
                sudo mkfs.fat -F 32 -n boot /dev/mmcblk0p1
                sudo mkfs.ext4 -L castit-os -F /dev/mmcblk0p2

                # 3. MOUNT & ENABLE SWAP (The Fix for Crashing)
                echo ">>> [3/5] Enabling Swap to prevent crash..."
                sudo mount /dev/mmcblk0p2 /mnt
                sudo mkdir -p /mnt/boot
                sudo mount /dev/mmcblk0p1 /mnt/boot
                
                sudo fallocate -l 4G /mnt/swapfile
                sudo chmod 600 /mnt/swapfile
                sudo mkswap /mnt/swapfile
                sudo swapon /mnt/swapfile

                # 4. Generate Hardware Config
                echo ">>> [4/5] Generating Hardware Config..."
                sudo nixos-generate-config --root /mnt

                # 5. Install (Redirecting temp files to disk)
                echo ">>> [5/5] Installing OS..."
                sudo mkdir -p /mnt/tmp
                export TMPDIR=/mnt/tmp

                sudo cp /etc/nixos-config/flake.nix /mnt/etc/nixos/
                sudo cp /etc/nixos-config/configuration.nix /mnt/etc/nixos/
                sudo cp /etc/nixos-config/logo.png /mnt/etc/nixos/

                # Propagate Keys from USB to SSD (if present)
                # In the live ISO, the root of the USB is usually /iso
                for key in ts-authkey ssh-key; do
                  if [ -f "/iso/$key" ]; then
                    echo "Found $key on USB, copying to target boot partition..."
                    sudo cp "/iso/$key" /mnt/boot/
                  fi
                done
                
                # We point to the baked-in config files inside /etc/nixos-config
                sudo -E nixos-install --flake /mnt/etc/nixos#intel-player --no-root-passwd --option cores 1 --option max-jobs 1 --impure
                
                echo "------------------------------------------------"
                echo "SUCCESS! Remove USB. Powering off in 10 seconds."
                echo "------------------------------------------------"
                sudo swapoff /mnt/swapfile
                sleep 10
                poweroff
              '')
            ];

            # Zero-Touch Automation Service
            systemd.services.auto-installer = {
              description = "Automated Castit OS Installer";
              after = [ "getty.target" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "simple";
                StandardInput = "tty";
                StandardOutput = "tty";
                StandardError = "tty";
                TTYPath = "/dev/tty1";
                ExecStart = "/run/current-system/sw/bin/auto-install";
              };
            };
          })
        ];
      };
    };
  };
}