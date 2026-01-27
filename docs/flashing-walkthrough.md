# Walkthrough: Burning Castit OS ISO on Linux

This guide walks through the process of burning the Castit OS ISO image to a USB drive on a Linux system.

## 1. Locate the ISO
The built ISO image is located in the `result` directory after building:
`result/iso/castit-24.11.20250630.50ab793-x86_64-linux.iso`

## 2. Identify the USB Drive
Before flashing, you must identify the correct device path for your USB drive. Run:
```bash
lsblk -p -o NAME,SIZE,MODEL,TYPE,TRAN | grep -v "loop"
```
Look for a device with `TYPE="disk"` and `TRAN="usb"`. For example, `/dev/sdb`.

## 3. Burn the ISO (CLI Method)
### Method A: bmaptool (Expert Shortcut - Fastest)

`bmaptool` is significantly faster than `dd` because it only writes the actual data blocks, skipping the empty space in the ISO image.

1.  **Install bmaptool**:
    -   Ubuntu/Debian: `sudo apt install bmap-tools`
    -   Fedora: `sudo dnf install bmap-tools`
    -   Nix: `nix-shell -p bmap-tools`
2.  **Unmount the drive (if needed)**:
    If the device is busy or automatically mounted by your system, unmount it first:
    ```bash
    udisksctl unmount -b /dev/sdb1
    ```
3.  **Flash**:
    ```bash
    sudo bmaptool copy --nobmap result/iso/castit-24.11.20250630.50ab793-x86_64-linux.iso /dev/sdb
    ```
    > [!TIP]
    > Use `--nobmap` if you haven't generated a `.bmap` file for the ISO.

### Method B: dd (Standard)

Use the `dd` command to copy the image to the USB drive. Replacing `/dev/sdb` with your actual device path:

```bash
sudo dd if=result/iso/castit-24.11.20250630.50ab793-x86_64-linux.iso of=/dev/sdb bs=4M status=progress conv=fsync
```

### Command Breakdown:
- `if=...`: Input file (the ISO).
- `of=...`: Output file (the USB device). **Warning: This erases the drive.**
- `bs=4M`: Read/write 4MB at a time for speed.
- `status=progress`: Shows a progress bar.
- `conv=fsync`: Ensures all data is physically written to the drive before finishing.

## 4. Verify the Flash
After `dd` or `bmaptool` completes, verify the partition table on the USB:
```bash
lsblk /dev/sdb
```
You should see at least two partitions.

## 5. Provisioning (Optional: Remote Access)
To enable Tailscale and SSH automatically, the recommended method is to **bake the keys into the ISO** during the build phase:

1.  **Place keys in project root**: Ensure `ts-authkey` and `ssh-key` are in your `castit-os` folder.
2.  **Add to Git (untracked)**: Run `git add -N ts-authkey ssh-key` so Nix can see them.
3.  **Build**: Run `nix build .#installer --impure`.
4.  **Flash**: Flash the resulting ISO using `bmaptool`.

> [!NOTE]
> Because the keys are embedded in the ISO, the Zero-Touch installer will automatically provision them to the target hardware. No manual copying to the USB is required after flashing.

## 6. Next Steps
1. Safely unplug the USB drive.
2. Plug it into the target Intel player hardware.
3. Boot from the USB.
4. **Zero-Touch**: The system will automatically skip the boot menu and start the installer.
5. **Safety**: Wait for the 20-second countdown (or press a key to cancel if needed).
