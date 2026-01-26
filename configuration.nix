{ config, pkgs, lib, ... }: {
  # 1. BOOTLOADER & HARDWARE
  networking.hostName = "castit-player";
  networking.networkmanager.enable = true; 
  time.timeZone = "Europe/Amsterdam"; 

  # 2. USER & DATA
  users.users.kiosk = {
    isNormalUser = true;
    extraGroups = [ "networkmanager" "video" "audio" "wheel" ];
    initialPassword = "castit-setup"; 
  };

  environment.systemPackages = [ pkgs.git ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # 3. GRAPHICS & AUDIO
  hardware.graphics.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
  security.rtkit.enable = true;

  # 4. KIOSK DISPLAY
  services.cage = {
    enable = true;
    user = "kiosk";
    environment = {
      XCURSOR_SIZE = "0";
    };
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
        "--remote-debugging-port=9222"
        "--check-for-update-interval=31536000"
        "--disable-hang-monitor"
        "--enable-logging=stderr --v=1"
        "--remote-allow-origins=*"
        "--disable-pinch"
        "--unlimited-storage"
        "--overscroll-history-navigation=0"        
      ];
      castit-url = "https://app.castit.nl/player/webPlayer";
    in "${pkgs.chromium}/bin/chromium ${builtins.concatStringsSep " " chromium-flags} ${castit-url}";
  };

  # 5. REMOTE ACCESS
  services.openssh.enable = true;
  services.tailscale.enable = true;
  systemd.services.tailscale-autoconnect = {
    description = "Automatic Tailscale Join";
    after = [ "network-pre.target" "tailscaled.service" ];
    wants = [ "network-pre.target" "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      sleep 5
      ${pkgs.tailscale}/bin/tailscale status | grep -v "Logged out" && exit 0
      [ ! -f /boot/ts-authkey ] && exit 0
      KEY=$(cat /boot/ts-authkey)
      ${pkgs.tailscale}/bin/tailscale up --authkey="$KEY"
    '';
  };

  # 6. AUTO UPDATER 
  systemd.services.update-signage = {
    description = "Pull latest configuration from Git and Apply";
    path = [ pkgs.git pkgs.nixos-rebuild pkgs.nix ];
    script = ''
      # 0. Safety Check
      echo "Starting Auto-Update as user: $(whoami)"

      # 1. Prepare Directory
      mkdir -p /etc/castit-os
      cd /etc/castit-os

      # 2. Clone or Reset
      if [ ! -d .git ]; then
        ${pkgs.git}/bin/git clone https://github.com/zrii/castit-os.git .
      else
        # We force reset to match origin/live exactly (discarding local manual changes)
        ${pkgs.git}/bin/git fetch origin
        ${pkgs.git}/bin/git reset --hard origin/live
      fi

      # 3. Apply the Configuration
      echo "Applying configuration..."
      ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch --flake .#intel-player --impure

      # 4. Restart the kiosk display
      echo "Restarting kiosk..."
      systemctl restart cage-tty1
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };
  systemd.timers.update-signage = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "1h";
      Unit = "update-signage.service";
    };
  };

  # 7. BRANDING (Silent Boot)
  boot.consoleLogLevel = 0;
  boot.initrd.verbose = false;
  boot.kernelParams = [
    "quiet" "splash" "boot.shell_on_fail" 
    "loglevel=3" "rd.systemd.show_status=false" 
    "rd.udev.log_level=3" "udev.log_priority=3"
  ];
  boot.plymouth = {
    enable = true;
    theme = "castit";
    themePackages = [
      (pkgs.stdenv.mkDerivation {
        name = "castit-boot-theme";
        src = ./.; 
        installPhase = ''
          mkdir -p $out/share/plymouth/themes/castit
          cp logo.png $out/share/plymouth/themes/castit/logo.png
          
          cat > $out/share/plymouth/themes/castit/castit.plymouth <<INI
          [Plymouth Theme]
          Name=Castit OS
          Description=Digital Signage Boot Theme
          ModuleName=script
          
          [script]
          ImageDir=$out/share/plymouth/themes/castit
          ScriptFile=$out/share/plymouth/themes/castit/castit.script
          INI
          
          cat > $out/share/plymouth/themes/castit/castit.script <<JS
          logo_image = Image("logo.png");
          screen_width = Window.GetWidth();
          screen_height = Window.GetHeight();
          logo_x = screen_width / 2 - logo_image.GetWidth() / 2;
          logo_y = screen_height / 2 - logo_image.GetHeight() / 2;
          sprite = Sprite(logo_image);
          sprite.SetPosition(logo_x, logo_y, 10000);
          Window.SetBackgroundTopColor(0, 0, 0);
          Window.SetBackgroundBottomColor(0, 0, 0);
          JS
        '';
      })
    ];
  };

  # 8. REBRANDING
  system.nixos.distroName = "Castit OS";
  system.nixos.distroId = "castit";

  system.stateVersion = "24.11";
}