# Remote Management Guide

## 1. SSH Access (Tailscale)
All Castit OS devices come with **Tailscale** pre-installed and enabled. This allows you to SSH into the players from anywhere, without port forwarding.

### How to use:
1.  **Tailscale Access**: 
    - Ensure you have a `ts-authkey` file in the root of your installation USB (or `/boot/ts-authkey` on the device).
    - The device will automatically join your Tailscale network on boot as `castit-<ID>`.
## 2. Provisioning Guide (The "Bake-in" Method)

To enable remote access automatically, you should "bake" your keys directly into the ISO image during the build process. This is the easiest and most reliable method.

### A. Prepare your keys in the project root
1.  **SSH Key**: Create a file named `ssh-key` (no extension) in your `castit-os` folder. Paste your public key(s) there.
    -   *To generate a new key*: `ssh-keygen -t ed25519 -C "admin@yourcompany.com" -f ~/.ssh/castit-ssh`
2.  **Tailscale Key**: Create a file named `ts-authkey` (no extension) in your `castit-os` folder. Paste your reusable Tailscale auth key there.

### B. Inform Nix about the files
If the files are not yet tracked by Git, Nix will ignore them. Run this command to tell Nix they exist:
```bash
git add -N ts-authkey ssh-key
```

### C. Build and Flash
1.  **Rebuild the ISO**: 
    ```bash
    nix build .#installer --impure
    ```
    Nix will automatically detect the files and embed them in the ISO.
2.  **Flash the USB**:
    ```bash
    sudo bmaptool copy result/iso/castit-*.iso /dev/sdX
    ```

> [!IMPORTANT]
> Because you "baked" the keys into the ISO, you don't need to manually mount or copy anything after flashing. The Zero-Touch installer will find the keys inside the ISO and move them to the final device for you.

---

## 3. Automatic Updates
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

## Debuging

- **SSH** - `ssh kiosk@[IP_ADDRESS]`
- **Tunnel the port 9222 for chrome debugging** - `ssh -L [LOCAL_PORT]:localhost:9222 kiosk@[IP_ADDRESS]`
- **Open chrome on your machine** - `chrome://inspect/#devices`
- **Add configuration** - `chrome://inspect/#devices` -> `Configure...` -> Add `localhost:[LOCAL_PORT]`