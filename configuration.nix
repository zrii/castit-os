{ config, pkgs, lib, ... }: {
  # 1. BOOTLOADER & HARDWARE
  networking.hostName = "castit-player";
  networking.networkmanager.enable = true; 
  time.timeZone = "Europe/Amsterdam"; 

  # 2. USER & DATA
  users.users.kiosk = {
    isNormalUser = true;
    extraGroups = [ "networkmanager" "video" "audio" ];
    initialPassword = "castit-setup"; 
  };

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
    description = "Pull latest configuration from Git";
    path = [ pkgs.git pkgs.nixos-rebuild pkgs.nix ];
    script = ''
      mkdir -p /etc/castit-os
      cd /etc/castit-os
      if [ ! -d .git ]; then
        ${pkgs.git}/bin/git clone https://github.com/zrii/castit-os.git . || true
      else
        ${pkgs.git}/bin/git pull || true