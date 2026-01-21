{
  description = "Castit Digital Signage OS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11"; # Stable channel
    nixos-hardware.url = "github:nixos/nixos-hardware"; # Hardware optimizations
  };

  outputs = { self, nixpkgs, nixos-hardware, ... }: {
    nixosConfigurations = {
      
      # Configuration for Raspberry Pi 4/5
      rpi-player = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          nixos-hardware.nixosModules.raspberry-pi-4  # Change to raspberry-pi-5 if needed
          ./configuration.nix
        ];
      };

      # Configuration for Intel NUC / Mini PC
      intel-player = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          ({ pkgs, modulesPath, ... }: {
            # NUC SPECIFIC SETTINGS
            boot.loader.grub.enable = false;
            boot.loader.systemd-boot.enable = true;
            boot.loader.efi.canTouchEfiVariables = true;
            # Drivers for common Intel hardware
            services.xserver.videoDrivers = [ "modesetting" ]; 
          })
        ];
      };
    };
  };
}