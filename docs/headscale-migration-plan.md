# Headscale Migration Plan

This document outlines the steps to migrate from Tailscale (hosted) to **Headscale** (self-hosted). Execute this when you're ready to move off Tailscale's free tier.

---

## Overview

| Component | Current (Tailscale) | After (Headscale) |
|-----------|---------------------|-------------------|
| Coordination Server | Tailscale Inc. | Your VPS |
| Client Software | tailscale | tailscale (same!) |
| Cost | Free (up to 100 devices) | ~$5/month VPS |
| Control | Limited | Full admin access |

---

## Prerequisites

- [ ] A VPS or server with a public IP (e.g., DigitalOcean, Hetzner, Linode)
- [ ] A domain name (e.g., `headscale.yourdomain.com`)
- [ ] SSL certificate (Let's Encrypt works)

---

## Part 1: Set Up Headscale Server

### Option A: NixOS Server (Recommended)

If your VPS runs NixOS, add this to its `configuration.nix`:

```nix
services.headscale = {
  enable = true;
  address = "0.0.0.0";
  port = 8080;
  settings = {
    server_url = "https://headscale.yourdomain.com";
    db_type = "sqlite3";
    db_path = "/var/lib/headscale/db.sqlite";
    private_key_path = "/var/lib/headscale/private.key";
    noise.private_key_path = "/var/lib/headscale/noise_private.key";
    ip_prefixes = [ "100.64.0.0/10" ];
    dns = {
      magic_dns = true;
      base_domain = "castit.local";
      nameservers.global = [ "1.1.1.1" "8.8.8.8" ];
    };
  };
};

# Reverse proxy with SSL
services.nginx = {
  enable = true;
  virtualHosts."headscale.yourdomain.com" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8080";
      proxyWebsockets = true;
    };
  };
};

security.acme = {
  acceptTerms = true;
  defaults.email = "admin@yourdomain.com";
};

networking.firewall.allowedTCPPorts = [ 80 443 ];
```

### Option B: Docker (Any Linux VPS)

```bash
# Create config directory
mkdir -p /etc/headscale

# Create config file
cat > /etc/headscale/config.yaml << 'EOF'
server_url: https://headscale.yourdomain.com
listen_addr: 0.0.0.0:8080
private_key_path: /etc/headscale/private.key
noise:
  private_key_path: /etc/headscale/noise_private.key
ip_prefixes:
  - 100.64.0.0/10
db_type: sqlite3
db_path: /etc/headscale/db.sqlite
dns:
  magic_dns: true
  base_domain: castit.local
  nameservers:
    global:
      - 1.1.1.1
EOF

# Run Headscale
docker run -d \
  --name headscale \
  -v /etc/headscale:/etc/headscale \
  -p 8080:8080 \
  headscale/headscale:latest \
  serve
```

Then set up Nginx/Caddy as a reverse proxy with SSL.

---

## Part 2: Create Namespace and Auth Key

```bash
# SSH into your Headscale server

# Create a namespace for castit devices
headscale namespaces create castit

# Generate a reusable pre-auth key (valid 1 year)
headscale preauthkeys create --namespace castit --reusable --expiration 8760h
```

Save the generated key (format: `hs-xxxxxxxxxx`).

---

## Part 3: Modify Castit OS Configuration

### Step 1: Update `configuration.nix`

Replace the Tailscale block with:

```nix
# In configuration.nix

services.tailscale = {
  enable = true;
  # Important: Point to YOUR Headscale server
  extraUpFlags = [
    "--login-server=https://headscale.yourdomain.com"
  ];
};

systemd.services.tailscale-autoconnect = {
  description = "Automatic Headscale Join";
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
    # Wait for network
    until ${pkgs.curl}/bin/curl -s --head --max-time 5 https://google.com > /dev/null 2>&1; do
      echo "Waiting for network..."
      sleep 2
    done
    echo "Network is up."

    # Skip if already connected
    if ${pkgs.tailscale}/bin/tailscale status 2>/dev/null | grep -q "100\." ; then
      echo "Already connected to Headscale."
      exit 0
    fi

    # Look for authkey
    if [ ! -f /boot/ts-authkey ]; then
      echo "No ts-authkey found. Skipping Headscale setup."
      exit 0
    fi

    KEY=$(cat /boot/ts-authkey)
    HOSTNAME="castit-$(cat /etc/castit-id 2>/dev/null || hostname)"
    echo "Joining Headscale as $HOSTNAME..."
    
    # KEY CHANGE: Add --login-server flag
    ${pkgs.tailscale}/bin/tailscale up \
      --login-server=https://headscale.yourdomain.com \
      --authkey="$KEY" \
      --hostname="$HOSTNAME"
    
    echo "Headscale connected!"
  '';
};
```

### Step 2: Update `ts-authkey`

Replace contents with your Headscale pre-auth key:

```bash
echo "hs-YOUR-HEADSCALE-KEY" > ts-authkey
git add ts-authkey
git commit -m "switch to headscale auth key"
git push origin master live
```

---

## Part 4: Migrate Existing Devices

For each existing Castit device:

```bash
# SSH into the device
ssh kiosk@<device-ip>

# Logout from Tailscale
sudo tailscale logout

# Update the auth key
echo "hs-YOUR-HEADSCALE-KEY" | sudo tee /boot/ts-authkey

# Force update to get new config
sudo systemctl start update-signage

# After update completes, connect to Headscale
sudo tailscale up \
  --login-server=https://headscale.yourdomain.com \
  --authkey="$(cat /boot/ts-authkey)" \
  --hostname="castit-$(cat /etc/castit-id)"

# Verify
sudo tailscale status
```

---

## Part 5: Verify and Monitor

### On Headscale Server

```bash
# List all connected nodes
headscale nodes list

# Check specific namespace
headscale nodes list --namespace castit
```

### On Castit Device

```bash
# Check connection status
sudo tailscale status

# Test connectivity to other nodes
sudo tailscale ping <other-device-ip>
```

---

## Rollback Plan

If something goes wrong, you can always go back to Tailscale:

```bash
# On the device
sudo tailscale logout
echo "tskey-auth-YOUR-TAILSCALE-KEY" | sudo tee /boot/ts-authkey
sudo tailscale up --authkey="$(cat /boot/ts-authkey)" --hostname="castit-$(cat /etc/castit-id)"
```

Then revert the `configuration.nix` changes and push.

---

## Quick Reference

| Action | Command |
|--------|---------|
| Create namespace | `headscale namespaces create <name>` |
| Create auth key | `headscale preauthkeys create --namespace <name> --reusable` |
| List nodes | `headscale nodes list` |
| Delete node | `headscale nodes delete --identifier <id>` |
| Register node manually | `headscale nodes register --namespace <name> --key <node-key>` |

---

## Resources

- [Headscale GitHub](https://github.com/juanfont/headscale)
- [Headscale Documentation](https://headscale.net/)
- [NixOS Headscale Module](https://search.nixos.org/options?query=services.headscale)
