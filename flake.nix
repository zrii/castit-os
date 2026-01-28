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
          ./hardware-configuration.nix 
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
            
            # Embed the config files into the ISO
            environment.etc."nixos-config/flake.nix".source = ./flake.nix;
            environment.etc."nixos-config/configuration.nix".source = ./configuration.nix;
            environment.etc."nixos-config/logo.png".source = ./logo.png;

            # Automatically embed keys if they exist in the project directory
            environment.etc."nixos-config/ts-authkey" = lib.mkIf (builtins.pathExists ./ts-authkey) {
              source = ./ts-authkey;
            };
            environment.etc."nixos-config/ssh-key" = lib.mkIf (builtins.pathExists ./ssh-key) {
              source = ./ssh-key;
            };

            # Added compatibility modules for Stage 1 boot
            boot.initrd.availableKernelModules = [ "uas" "xhci_pci" "usb_storage" "vmd" "nvme" "ahci" "sd_mod" ];

            # The "Low Memory" Automation Script with Interactive Disk Selection
            environment.systemPackages = [
              (pkgs.writeShellScriptBin "auto-install" ''
                set -e
                echo "=============================================="
                echo "       CASTIT OS INSTALLER"
                echo "=============================================="
                echo ""

                # --- DISK SELECTION ---
                echo "Available disks:"
                echo ""
                
                # List disks (exclude loop, ram, and the USB installer itself)
                mapfile -t DISKS < <(lsblk -d -n -o NAME,SIZE,MODEL,TYPE | grep -E "disk$" | grep -v "loop" | awk '{print $1}')
                
                if [ ''${#DISKS[@]} -eq 0 ]; then
                  echo "ERROR: No suitable disks found!"
                  exit 1
                fi

                # Display numbered list
                for i in "''${!DISKS[@]}"; do
                  DISK="''${DISKS[$i]}"
                  INFO=$(lsblk -d -n -o SIZE,MODEL /dev/$DISK 2>/dev/null | xargs)
                  echo "  $((i+1))) $DISK - $INFO"
                done
                echo ""

                # Get user selection
                while true; do
                  read -p "Select target disk [1-''${#DISKS[@]}]: " CHOICE
                  if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "''${#DISKS[@]}" ]; then
                    TARGET_DISK="/dev/''${DISKS[$((CHOICE-1))]}"
                    break
                  fi
                  echo "Invalid selection. Please try again."
                done

                # Determine partition naming (nvme/mmc use 'p1', others use '1')
                if [[ "$TARGET_DISK" == *"nvme"* ]] || [[ "$TARGET_DISK" == *"mmcblk"* ]]; then
                  PART1="''${TARGET_DISK}p1"
                  PART2="''${TARGET_DISK}p2"
                else
                  PART1="''${TARGET_DISK}1"
                  PART2="''${TARGET_DISK}2"
                fi

                echo ""
                echo "!!! WARNING: THIS WILL COMPLETELY WIPE $TARGET_DISK !!!"
                echo "    EFI Partition: $PART1"
                echo "    Root Partition: $PART2"
                echo ""
                read -p "Type 'yes' to confirm: " CONFIRM
                if [ "$CONFIRM" != "yes" ]; then
                  echo "Installation cancelled."
                  exit 1
                fi

                echo ""
                echo "--- STARTING INSTALLATION ---"

                # 1. Manual Partitioning (Uses less RAM than Disko)
                echo ">>> [1/5] Partitioning $TARGET_DISK..."
                sudo parted -s $TARGET_DISK mklabel gpt
                sudo parted -s $TARGET_DISK mkpart ESP fat32 1MiB 512MiB
                sudo parted -s $TARGET_DISK set 1 esp on
                sudo parted -s $TARGET_DISK mkpart primary ext4 512MiB 100%
                
                # 2. Format
                echo ">>> [2/5] Formatting..."
                sudo mkfs.fat -F 32 -n boot $PART1
                sudo mkfs.ext4 -L castit-os -F $PART2

                # 3. MOUNT & ENABLE SWAP (The Fix for Crashing)
                echo ">>> [3/5] Enabling Swap to prevent crash..."
                sudo mount $PART2 /mnt
                sudo mkdir -p /mnt/boot
                sudo mount $PART1 /mnt/boot
                
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

                # Propagate Keys (Primary: Embedded in ISO, Fallback: USB root)
                for key in ts-authkey ssh-key; do
                  if [ -f "/etc/nixos-config/$key" ]; then
                    echo "Found embedded $key, copying to target boot partition..."
                    sudo cp "/etc/nixos-config/$key" /mnt/boot/
                  elif [ -f "/iso/$key" ]; then
                    echo "Found $key on USB root, copying to target boot partition..."
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