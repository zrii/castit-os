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

      # 2. THE INSTALLER ISO (Automation Tool)
      installer = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-graphical-calamares-gnome.nix"
          ({ pkgs, ... }: {
            # Bake config files into the ISO
            environment.etc."nixos-config".source = ./.;
            
            # The Automated Script with Countdown
            environment.systemPackages = [
              (pkgs.writeShellScriptBin "auto-install" ''
                set -e
                echo "--- STARTING CASTIT AUTOMATED INSTALL ---"
                
                # 1. Partition & Mount (Disko)
                echo ">>> Wiping and Partitioning /dev/mmcblk0..."
                sudo nix --experimental-features "nix-command flakes" \
                  run github:nix-community/disko -- --mode disko --flake /etc/nixos-config#intel-player

                # 2. Generate Hardware Config
                echo ">>> Generating Hardware ID..."
                sudo nixos-generate-config --no-filesystems --root /mnt

                # 3. Install
                echo ">>> Installing OS..."
                sudo nixos-install --flake /etc/nixos-config#intel-player --no-root-passwd
                
                # 4. Success & Countdown
                echo "====================================================="
                echo "   INSTALLATION SUCCESSFUL"
                echo "====================================================="
                echo "Please REMOVE the USB drive now."
                echo "The system will POWER OFF automatically in 20 seconds."
                echo "====================================================="
                
                for i in {20..1}; do
                  echo -ne "Powering off in $i... \r"
                  sleep 1
                done
                
                echo "Goodnight!"
                poweroff
              '')
            ];
          })
        ];
      };
    };
  };
}