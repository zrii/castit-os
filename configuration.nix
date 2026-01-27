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
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG6IwHAG097lffn7PFKc89TWd3QYQhPSMILGnSKcVwa+ z.popovic@futureforward.rs"
    ];
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
  security.rtkit.enable = true;[kiosk@castit-player:~]$ # 1. Check if the ts-authkey file exists
ls -la /boot/ts-authkey
# 2. Check Tailscale service status
sudo systemctl status tailscale-autoconnect
# 3. Check Tailscale service logs
sudo journalctl -u tailscale-autoconnect -n 50
# 4. Check current Tailscale state
sudo tailscale status
ls: cannot access '/boot/ts-authkey': No such file or directory
[sudo] password for kiosk: 
● tailscale-autoconnect.service - Automatic Tailscale Join
     Loaded: loaded (/etc/systemd/system/tailscale-autoconnect.service; enabled; preset: ignored)
     Active: activating (start) since Tue 2026-01-27 17:36:33 CET; 5min ago
 Invocation: 1d3a1e268b3646eb82efa483711e7581
   Main PID: 1112 (tailscale-autoc)
         IP: 1.1M in, 265.2K out
         IO: 1.8M read, 0B written
      Tasks: 3 (limit: 4474)
     Memory: 6.1M (peak: 6.9M)
        CPU: 6.652s
     CGroup: /system.slice/tailscale-autoconnect.service
             ├─1112 /nix/store/mjhcjikhxps97mq5z54j4gjjfzgmsir5-bash-5.2p37/bin/bash /nix/store/snvzdd11hzf0nxfj4ixl629c2800idyq-unit-script-tailscale-autoconnect-start>
             ├─1758 /nix/store/xr777l6vdpkdi16h9dpv89l3s6hp17h9-curl-8.12.1-bin/bin/curl -s --head --request GET https://google.com
             └─1759 grep "200 OK"

Jan 27 17:36:33 castit-player systemd[1]: Starting Automatic Tailscale Join...
lines 1-16/16 (END)


  # 4. KIOSK DISPLAY
  services.cage = {
    enable = true;
    user = "kiosk";
    environment = {
      XCURSOR_SIZE = "0";
    };
    program = pkgs.writeShellScript "castit-browser" ''
      # 1. Get or Generate ID
      if [ -f /etc/castit-id ]; then
        CID=$(cat /etc/castit-id)
      else
        CID="unknown"
      fi

      # 2. Define Flags
      FLAGS=(
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
        "--remote-allow-origins=*"
        "--disable-pinch"
        "--unlimited-storage"
        "--overscroll-history-navigation=0"
      )

      # 3. Start Browser
      URL="https://app.castit.nl/player/webPlayer?cid=$CID"
      exec ${pkgs.chromium}/bin/chromium "''${FLAGS[@]}" "$URL"
    '';
  };

  # 5. REMOTE ACCESS
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = lib.mkForce true; # Default, but we might override
      PermitRootLogin = "no";
    };
  };

  # SSH Key Auto-Import (From USB)
  # This is for "Zero-Touch" setup on new devices.
  # For permanent management, add keys to users.users.kiosk.openssh.authorizedKeys.keys above.
  systemd.services.ssh-key-import = {
    description = "Import SSH keys from boot partition";
    before = [ "sshd.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      # 1. Check for key on boot
      if [ -f /boot/ssh-key ]; then
        echo "Found ssh-key on boot. Importing..."
        mkdir -p /home/kiosk/.ssh
        
        # Add keys selectively (avoid duplicates)
        while IFS= read -r key; do
          if ! grep -qxF "$key" /home/kiosk/.ssh/authorized_keys 2>/dev/null; then
            echo "$key" >> /home/kiosk/.ssh/authorized_keys
          fi
        done < /boot/ssh-key

        chmod 700 /home/kiosk/.ssh
        chmod 600 /home/kiosk/.ssh/authorized_keys
        chown -R kiosk:users /home/kiosk/.ssh
      fi
    '';
  };

  services.tailscale.enable = true;
  systemd.services.tailscale-autoconnect = {
    description = "Automatic Tailscale Join";
    after = [ "network-online.target" "tailscaled.service" ];
    wants = [ "network-online.target" "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      Restart = "on-failure";
      RestartSec = "10s";
    };
    script = ''
      set -e
      # Wait for network (use curl exit code, works with HTTP/2)
      until ${pkgs.curl}/bin/curl -s --head --max-time 5 https://google.com > /dev/null 2>&1; do
        echo "Waiting for network..."
        sleep 2
      done
      echo "Network is up."

      # Skip if already connected
      if ${pkgs.tailscale}/bin/tailscale status 2>/dev/null | grep -q "100\." ; then
        echo "Already connected to Tailscale."
        exit 0
      fi

      # Look for authkey
      if [ ! -f /boot/ts-authkey ]; then
        echo "No ts-authkey found at /boot/ts-authkey. Skipping Tailscale setup."
        exit 0
      fi

      KEY=$(cat /boot/ts-authkey)
      HOSTNAME="castit-$(cat /etc/castit-id 2>/dev/null || hostname)"
      echo "Joining Tailscale as $HOSTNAME..."
      ${pkgs.tailscale}/bin/tailscale up --authkey="$KEY" --hostname="$HOSTNAME"
      echo "Tailscale connected!"
    '';
  };

  # 6. CASTIT CORE SERVICES (ID Generation)
  systemd.services.castit-init = {
    description = "Initialize Castit Machine Identity";
    before = [ "cage-tty1.service" "tailscale-autoconnect.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      if [ ! -f /etc/castit-id ]; then
        # Try Product UUID, else Fallback to machine-id
        if [ -f /sys/class/dmi/id/product_uuid ]; then
           cat /sys/class/dmi/id/product_uuid | tr -d '-' | cut -c1-12 > /etc/castit-id
        else
           cat /etc/machine-id | cut -c1-12 > /etc/castit-id
        fi
      fi
    '';
  };

  # 7. AUTO UPDATER 
  systemd.services.update-signage = {
    description = "Pull latest configuration from Git and Apply";
    path = [ pkgs.git pkgs.nixos-rebuild pkgs.nix pkgs.util-linux ];
    script = ''
      set -e
      LOG_TAG="[UPDATE]"
      echo "$LOG_TAG Starting update check at $(date)"

      # 1. Prepare Directory
      mkdir -p /etc/castit-os
      cd /etc/castit-os

      # 2. Get Current Version
      CURRENT_REV="unknown"
      [ -d .git ] && CURRENT_REV=$(${pkgs.git}/bin/git rev-parse --short HEAD)
      echo "$LOG_TAG Current revision: $CURRENT_REV"

      # 3. Fetch and Compare
      echo "$LOG_TAG [FETCH] Checking remote repository..."
      if [ ! -d .git ]; then
        ${pkgs.git}/bin/git clone https://github.com/zrii/castit-os.git .
      else
        ${pkgs.git}/bin/git fetch origin
      fi
      
      TARGET_REV=$(${pkgs.git}/bin/git rev-parse --short origin/live)
      echo "$LOG_TAG Target revision: $TARGET_REV"

      if [ "$CURRENT_REV" = "$TARGET_REV" ]; then
        echo "$LOG_TAG [SKIP] Already up to date."
        exit 0
      fi

      # 4. Apply
      echo "$LOG_TAG [APPLY] Resetting to $TARGET_REV..."
      ${pkgs.git}/bin/git reset --hard origin/live

      echo "$LOG_TAG [BUILD] Rebuilding system..."
      ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch --flake .#intel-player --impure

      # 5. Restart
      echo "$LOG_TAG [RESTART] Refreshing display..."
      systemctl restart cage-tty1
      
      echo "$LOG_TAG [DONE] Update successful."
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