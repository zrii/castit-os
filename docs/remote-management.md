# Remote Management Guide

## 1. SSH Access (Tailscale)
All Castit OS devices come with **Tailscale** pre-installed and enabled. This allows you to SSH into the players from anywhere, without port forwarding.

### How to use:
1.  **Tailscale Access**: 
    - Ensure you have a `ts-authkey` file in the root of your installation USB (or `/boot/ts-authkey` on the device).
    - The device will automatically join your Tailscale network on boot as `castit-<ID>`.
2.  **SSH Access**:
    - Place your public SSH key in a file named `ssh-key` in the root of the installation USB.
    - **Multiple Keys**: You can paste multiple public keys into the same `ssh-key` file (one per line). This allows multiple administrators to access the player.
    - The system will automatically add them to the `kiosk` user's `authorized_keys` on boot.
3.  **Machine Identity**:
    - Access the device via Tailscale: `ssh kiosk@castit-<ID>` (where `<ID>` is the 12-char hardware ID shown in the URL or `/etc/castit-id`).

---

## 2. Provisioning Guide (How to prepare your USB)

To enable remote access automatically, you need to place two files on the root of your bootable USB stick **after flashing it**.

### A. Generating an SSH Key
If you don't already have an SSH key, you can generate one on your computer:

1.  **Open a terminal** (Linux/Mac) or PowerShell (Windows).
2.  **Run**: `ssh-keygen -t ed25519 -C "admin@yourcompany.com"  -f ~/.ssh/castit-ssh`
3.  Press Enter to save to the default location.
4.  **Find your public key**:
    -   Linux/Mac: `cat ~/.ssh/castit-ssh.pub`
    -   Windows: `cat $HOME\.ssh\castit-ssh.pub`
5.  **Create the file**: Create a file named `ssh-key` (no extension) on your USB and paste that long string into it.

### C. (Recommended) Git-Based Key Management
Instead of using the USB for every device, you can manage keys centrally in the code:

1.  Open `configuration.nix`.
2.  Find the `users.users.kiosk.openssh.authorizedKeys.keys` list.
3.  Paste your public keys there.
4.  **Commit and push** to the `live` branch.
5.  **All players** will automatically pull this update within an hour and grant you access.

> [!TIP]
> Use the **USB Method** for the very first installation of a device. Once it's online and updating itself, use the **Git Method** to add/remove administrators or update your own keys.

### D. Getting a Tailscale Auth Key
1.  Log in to your [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys).
2.  Go to **Settings** -> **Keys**.
3.  Click **Generate auth key**.
4.  **Recommended Settings**:
    -   **Reusable**: Yes (if you are deploying multiple players).
    -   **Ephemeral**: No.
    -   **Pre-authorized**: Yes.
5.  **Create the file**: Copy the key (starting with `tskey-auth-...`) and paste it into a file named `ts-authkey` (no extension) on the root of your USB.

> [!TIP]
> Once the device boots and joins your network, you can manage it from the Tailscale dashboard. You can even use "Device Settings" in Tailscale to disable key expiry for your signage players so they stay connected forever.

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