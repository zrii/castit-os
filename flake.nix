{
  description = "Castit Digital Signage OS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11"; 
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, disko, ... }: {
    nixosConfigurations = {
      
      # 1. THE PLAYER CONFIGURATION (Target System)
      intel-player = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          ./configuration.nix
          # Automated Partitioning
          {
            disko.devices.disk.main = {
              device = "/dev/mmcblk0"; 
              type = "disk";
              content = {
                type = "gpt";
                partitions = {
                  ESP = {
                    size = "512M";
                    type = "EF00";
                    content = {
                      type = "filesystem";
                      format = "vfat";
                      mountpoint = "/boot";
                    };
                  };
                  root = {
                    size = "100%";
                    content = {
                      type = "filesystem";
                      format = "ext4";
                      mountpoint = "/";
                    };
                  };
                };
              };
            };
          }
          ({ pkgs, ... }: {
            boot.loader.systemd-boot.enable = true;
            boot.loader.efi.canTouchEfiVariables = true;
          })
        ];
      };

      # 2. THE INSTALLER ISO (With Crash Fixes)
      installer = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-graphical-calamares-gnome.nix"
          ({ pkgs, ... }: {
            environment.etc."nixos-config".source = ./.;
            
            environment.systemPackages = [
              (pkgs.writeShellScriptBin "auto-install" ''
                set -e
                echo "--- STARTING CASTIT AUTOMATED INSTALL (SAFE MODE) ---"
                
                # 1. Partition & Format
                echo ">>> [1/5] Partitioning Drive..."
                sudo nix --experimental-features "nix-command flakes" \
                  run github:nix-community/disko -- --mode disko --flake /etc/nixos-config#intel-player

                # 2. CREATE SWAP (CRITICAL FIX FOR CRASHES)
                # We use the newly formatted SSD to extend RAM so the installer doesn't die.
                echo ">>> [2/5] Creating 4GB Swap File to prevent RAM crash..."
                sudo fallocate -l 4G /mnt/swapfile
                sudo chmod 600 /mnt/swapfile
                sudo mkswap /mnt/swapfile
                sudo swapon /mnt/swapfile
                
                # 3. Hardware Config
                echo ">>> [3/5] Generating Hardware Config..."
                sudo nixos-generate-config --no-filesystems --root /mnt

                # 4. Install (With diverted TMPDIR)
                echo ">>> [4/5] Installing OS (This may take time)..."
                # We tell Nix to use the disk for temporary files, not RAM
                export TMPDIR=/mnt/tmp
                mkdir -p $TMPDIR
                sudo -E nixos-install --flake /etc/nixos-config#intel-player --no-root-passwd
                
                # 5. Cleanup & Countdown
                echo "====================================================="
                echo "   INSTALLATION SUCCESSFUL"
                echo "====================================================="
                echo "Please REMOVE the USB drive now."
                echo "System will Power Off in 20 seconds."
                echo "====================================================="
                
                # Turn off swap before finishing to be safe
                sudo swapoff /mnt/swapfile || true
                
                for i in {20..1}; do
                  echo -ne "Powering off in $i... \r"
                  sleep 1
                done
                
                poweroff
              '')
            ];
          })
        ];
      };
    };
  };
}