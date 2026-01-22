{
  description = "Castit Digital Signage OS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11"; 
    nixos-hardware.url = "github:nixos/nixos-hardware";
  };

  outputs = { self, nixpkgs, nixos-hardware, ... }: {
    nixosConfigurations = {
      
      # 1. THE ACTUAL PLAYER (Target for the SSD)
      # This is what you install ONTO the NUC's internal drive.
      intel-player = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          # Import the hardware config generated during installation
          ./hardware-configuration.nix 
          ({ pkgs, ... }: {
            boot.loader.systemd-boot.enable = true; [cite: 34]
            boot.loader.efi.canTouchEfiVariables = true; [cite: 34]
            services.xserver.videoDrivers = [ "modesetting" ]; [cite: 34, 35]
          })
        ];
      };

      # 2. THE GRAPHICAL INSTALLER (The Flash Drive)
      # This builds the ISO you boot from in WSL.
      installer = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          # Provides the GNOME graphical installer environment
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-graphical-calamares-gnome.nix" [cite: 32]
          
          # This ensures your signage config files are available on the Live USB
          ({ pkgs, ... }: {
            environment.systemPackages = [ pkgs.git pkgs.vim ];
            # Optional: Pre-configure networking or SSH for the installer if needed
          })
        ];
      };

      # --- RASPBERRY PI PLAYER ---
      rpi-player = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          nixos-hardware.nixosModules.raspberry-pi-4 [cite: 37]
          ./configuration.nix [cite: 37]
          ({ pkgs, ... }: {
            boot.loader.grub.enable = false; [cite: 37]
            boot.loader.generic-extlinux-compatible.enable = true; [cite: 37]
          })
        ];
      };
    };
  };
}