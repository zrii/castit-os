# Remote Management Guide

## 1. SSH Access (Tailscale)
All Castit OS devices come with **Tailscale** pre-installed and enabled. This allows you to SSH into the players from anywhere, without port forwarding.

### How to use:
1.  Ensure you have a `ts-authkey` file in the root of your installation USB (or `/boot/ts-authkey` on the device).
2.  The device will automatically join your Tailscale network on boot.
3.  Access the device using its hostname or Tailscale IP:
    ```bash
    ssh zri@castit-player
    ```
    *(Note: Default user is `kiosk` which has no password, but SSH usually requires a key or configured user. You may need to configure an authorized key in `configuration.nix` if you want direct SSH access, or just use Tailscale's "MagicDNS" features if configured.)*

## 2. Automatic Updates
The device checks for updates **2 minutes** after boot, and then every **1 hour**.

### How it works:
1.  The `update-signage` service runs automatically.
2.  It pulls the latest code from `https://github.com/zrii/castit-os`.
3.  It performs a **hard reset** to match the `live` branch (overwriting local changes).
4.  It runs `nixos-rebuild switch` to apply the new configuration.

### Triggering a Manual Update
If you have SSH access, you can force an immediate update:

```bash
sudo systemctl start update-signage
```

### Monitoring Updates

**Check the status of the last update:**
```bash
sudo systemctl status update-signage
```

**View update logs:**
```bash
sudo journalctl -u update-signage
```

**View real-time logs while running:**
```bash
sudo journalctl -u update-signage -f
```

**Check when the next automatic update is scheduled:**
```bash
systemctl list-timers update-signage
```

The update service runs:
- **2 minutes after boot** 
- **Every hour thereafter**
