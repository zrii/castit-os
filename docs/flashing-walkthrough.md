# Walkthrough: Burning Castit OS ISO on Linux

This guide walks through the process of burning the Castit OS ISO image to a USB drive on a Linux system.

## 1. Locate the ISO
The built ISO image is located in the `result` directory after building:
`result/iso/nixos-24.11.20250630.50ab793-x86_64-linux.iso`

## 2. Identify the USB Drive
Before flashing, you must identify the correct device path for your USB drive. Run:
```bash
lsblk -p -o NAME,SIZE,MODEL,TYPE,TRAN | grep -v "loop"
```
Look for a device with `TYPE="disk"` and `TRAN="usb"`. For example, `/dev/sdb`.

## 3. Burn the ISO (CLI Method)
Use the `dd` command to copy the image to the USB drive. Replacing `/dev/sdX` with your actual device path:

```bash
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

### Command Breakdown:
- `if=...`: Input file (the ISO).
- `of=...`: Output file (the USB device). **Warning: This erases the drive.**
- `bs=4M`: Read/write 4MB at a time for speed.
- `status=progress`: Shows a progress bar.
- `conv=fsync`: Ensures all data is physically written to the drive before finishing.

## 4. Verify the Flash
After `dd` completes, verify the partition table on the USB:
```bash
lsblk /dev/sdX
```
You should see at least two partitions:
1. A large partition (the Castit OS system).
2. A small EFI partition.

## 5. Next Steps
1. Safely unplug the USB drive.
2. Plug it into the target Intel player hardware.
3. Boot from the USB.
4. Run `auto-install` to begin the automated setup.
