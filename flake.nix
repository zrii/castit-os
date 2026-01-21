{
  description = "Castit Digital Signage OS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11"; 
    nixos-hardware.url = "github:nixos/nixos-hardware"; 
  };

  outputs = { self, nixpkgs, nixos-hardware, ... }: {
    nixosConfigurations = {
      
      # --- INTEL NUC PLAYER ---
      intel-player = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          ({ pkgs, ... }: {
            # REQUIRED FOR INTEL NUC BOOT
            boot.loader.grub.enable = false;
            boot.loader.systemd-boot.enable = true;
            boot.loader.efi.canTouchEfiVariables = true;
            services.xserver.videoDrivers = [ "modesetting" ];
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
            # RPi Specifics
            boot.loader.grub.enable = false;
            boot.loader.generic-extlinux-compatible.enable = true;
          })
        ];
      };

    };
  };
}