{
  description = "Castit Digital Signage OS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11"; 
    nixos-hardware.url = "github:nixos/nixos-hardware";
  };

  outputs = { self, nixpkgs, nixos-hardware, ... }: {
    nixosConfigurations = {
      
      # --- INTEL NUC PLAYER (Permanent SSD Install) ---
      intel-player = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          # Note: hardware-configuration.nix is required for the final install
          ({ pkgs, ... }: {
            boot.loader.grub.enable = false;
            boot.loader.systemd-boot.enable = true;
            boot.loader.efi.canTouchEfiVariables = true;
            services.xserver.videoDrivers = [ "modesetting" ];
          })
        ];
      };

      # --- GRAPHICAL INSTALLER (The Flash Drive) ---
      installer = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-graphical-calamares-gnome.nix"
          ({ pkgs, ... }: {
            # Extra tools for the live environment
            environment.systemPackages = [ pkgs.git pkgs.vim ];
          })
        ];
      };

      # --- RASPBERRY PI PLAYER ---
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