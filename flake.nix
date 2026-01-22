{
  description = "Castit Digital Signage OS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11"; 
    nixos-hardware.url = "github:nixos/nixos-hardware";
  };

  outputs = { self, nixpkgs, nixos-hardware, ... }: {
    nixosConfigurations = {
      
      # 1. THE ACTUAL PLAYER (Target for the SSD)
      intel-player = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          # This will be created on the NUC later
          ./hardware-configuration.nix 
          ({ pkgs, ... }: {
            boot.loader.systemd-boot.enable = true;
            boot.loader.efi.canTouchEfiVariables = true;
            services.xserver.videoDrivers = [ "modesetting" ];
          })
        ];
      };

      # 2. THE GRAPHICAL INSTALLER (The Flash Drive)
      installer = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          # Standard graphical installer module
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-graphical-calamares-gnome.nix"
          ({ pkgs, ... }: {
            environment.systemPackages = [ pkgs.git pkgs.vim ];
          })
        ];
      };

      # 3. RASPBERRY PI PLAYER
      rpi-player = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          nixos-hardware.nixosModules.raspberry-pi-4
          ./configuration.nix
          ({ pkgs, ... }: {
            boot.loader.grub.enable = false;
            boot.loader.generic-extlinux-compatible.enable = true;
          })
        ];
      };
    };
  };
}