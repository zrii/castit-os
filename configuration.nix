{ config, pkgs, lib, ... }: {

  # ==========================================
  # 1. BOOTLOADER & HARDWARE
  # ==========================================
  # We leave bootloader config to the flake (differs for Pi vs Intel)
  networking.hostName = "castit-player";
  networking.networkmanager.enable = true; 
  time.timeZone = "Europe/Amsterdam"; 

  # ==========================================
  # 2. USER & DATA
  # ==========================================
  users.users.kiosk = {
    isNormalUser = true;
    extraGroups = [ "networkmanager" "video" "audio" ];
    initialPassword = "castit-setup"; # <--- CHANGE FOR PRODUCTION
  };

  # ==========================================
  # 3. GRAPHICS & AUDIO
  # ==========================================
  hardware.graphics.enable = true; 
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
  security.rtkit.enable = true;

  # ==========================================
  # 4. KIOSK DISPLAY
  # ==========================================
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
        "--enable-features=OverlayScrollbar,VaapiVideoDecoder,VaapiVideoEncoder" 
        "--ignore-gpu-blocklist"
        "--enable-gpu-rasterization"
        "--enable-zero-copy"
      ];
      castit-url = "https://app.castit.nl/player/webPlayer";
    in "${pkgs.chromium}/bin/chromium ${builtins.concatStringsSep " " chromium-flags} ${castit-url}";
  };

  # ==========================================
  # 5. REMOTE ACCESS (Tailscale Auto-Join)
  # ==========================================
  services.openssh.enable = true;
  services.tailscale.enable = true;

  # This script runs on boot. If it finds 'ts-authkey' on the boot partition,
  # it logs the device into your Tailscale network automatically.
  systemd.services.tailscale-autoconnect = {
    description = "Automatic Tailscale Join";
    after = [ "network-pre.target" "tailscaled.service" ];
    wants = [ "network-pre.target" "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      # Wait for tailscale to settle
      sleep 5
      
      # Check if we are already logged in
      if ${pkgs.tailscale}/bin/tailscale status | grep -q "Logged out"; then
        # Look for key on boot partition (works for RPi and many USB installs)
        if [ -f /boot/ts-authkey ]; then
          KEY=$(cat /boot/ts-authkey)
          ${pkgs.tailscale}/bin/tailscale up --authkey=$KEY
        fi
      fi
    '';
  };

  # ==========================================
  # 6. AUTO UPDATER (The Real Code)
  # ==========================================
  # This creates a background service that pulls your git repo
  systemd.services.update-signage = {
    description = "Pull latest configuration from Git";
    path = [ pkgs.git pkgs.nixos-rebuild pkgs.nix ];
    script = ''
      # 1. Setup Directory
      mkdir -p /etc/castit-os
      cd /etc/castit-os

      # 2. Clone if empty, otherwise Pull
      if [ ! -d .git ]; then
        # REPLACE THIS URL WITH YOUR REAL REPO LATER
        ${pkgs.git}/bin/git clone https://github.com/YOUR_USER/castit-os.git .
      else
        ${pkgs.git}/bin/git pull
      fi

      # 3. Apply Update (Uncomment the next line when you have a real repo!)
      # nixos-rebuild switch --flake .#intel-player
    '';
  };

  # ==========================================
  # 7. BRANDING (Silent Boot)
  # ==========================================
  boot.plymouth = {
    enable = true;
    # You can choose standard themes like "bgrt" (uses OEM logo) or "spinner"
    # To use a custom Castit logo requires creating a custom theme package (see below)
  };

  # Hide the "scrolling text" during boot
  boot.consoleLogLevel = 0;
  boot.initrd.verbose = false;
  boot.kernelParams = [
    "quiet"
    "splash"
    "boot.shell_on_fail"
    "loglevel=3"
    "rd.systemd.show_status=false"
    "rd.udev.log_level=3"
    "udev.log_priority=3"
  ];

  # Run the updater 10 minutes after boot, and then every hour
  systemd.timers.update-signage = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10m";
      OnUnitActiveSec = "1h";
      Unit = "update-signage.service";
    };
  };

  system.stateVersion = "24.11";
}