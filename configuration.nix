{ config, pkgs, lib, ... }: {

  # --- 1. System Basics ---
  boot.loader.grub.enable = false;
  # Use generic-extlinux for RPi, systemd-boot for Intel (auto-detected usually, but keep simple)
  boot.loader.generic-extlinux-compatible.enable = lib.mkDefault true;
  
  networking.hostName = "castit-player";
  networking.networkmanager.enable = true; # Allow Wifi/Ethernet easy setup
  time.timeZone = "Europe/Amsterdam"; # Set your default

  # --- 2. User & Persistence (Critical for Castit Hash) ---
  # We create a normal user. Data in /home/kiosk is PERSISTENT by default.
  users.users.kiosk = {
    isNormalUser = true;
    extraGroups = [ "networkmanager" "video" "audio" ];
    initialPassword = "castit-setup"; # Change this or use SSH keys!
  };

  # --- 3. Graphics & Audio ---
  hardware.graphics.enable = true; # Enable GPU acceleration
  sound.enable = true;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # --- 4. The Kiosk Engine (Cage + Chromium) ---
  services.cage = {
    enable = true;
    user = "kiosk";
    program = let
      chromium-flags = [
        "--kiosk"
        "--no-first-run"
        "--no-default-browser-check"
        "--noerrdialogs"
        "--disable-infobars"
        "--disable-session-crashed-bubble"
        "--autoplay-policy=no-user-gesture-required"
        "--enable-features=OverlayScrollbar,VaapiVideoDecoder,VaapiVideoEncoder" # Hardware Accel
        "--ignore-gpu-blocklist"
        "--enable-gpu-rasterization"
        "--enable-zero-copy"
      ];
      castit-url = "https://app.castit.nl/player/webPlayer";
    in "${pkgs.chromium}/bin/chromium ${builtins.concatStringsSep " " chromium-flags} ${castit-url}";
  };

  # --- 5. Remote Access (Tailscale) ---
  services.tailscale.enable = true;
  # You will need to run 'sudo tailscale up' once manually, 
  # or use an Auth Key in a systemd 'preStart' script to auto-join on first boot.

  # --- 6. Remote Updates (The "Pull" Method) ---
  # This sets up a timer to pull the latest config from your Git repo
  services.git-sync = {
     enable = true;
     user = "root";
     uri = "https://github.com/YOUR_ORG/castit-os-config.git";
     branch = "main";
     localDir = "/etc/nixos";
     interval = 3600; # Check every hour
  };
  # Note: You need a script to run 'nixos-rebuild switch' after sync. 
  # Alternatively, use the specific tool "comin" which does this automatically.

  # --- 7. SSH Access ---
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true; # Set to false and use keys for production!
  };
  
  system.stateVersion = "24.11";
}