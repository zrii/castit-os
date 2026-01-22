{
  description = "Castit Digital Signage OS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11"; 
  };

  outputs = { self, nixpkgs, ... }: {
    nixosConfigurations = {
      
      # The configuration for the Physical NUC Player
      intel-player = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          ./hardware-configuration.nix
          ({ pkgs, ... }: {
            # Use systemd-boot (Required for UEFI NUCs)
            boot.loader.systemd-boot.enable = true;
            boot.loader.efi.canTouchEfiVariables = true;
          })
        ];
      };
    };
  };
}