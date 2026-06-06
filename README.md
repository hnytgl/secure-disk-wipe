# Secure Disk Wipe

A Windows PowerShell script that formats a volume and then wipes the free space with three overwrite passes — suitable for sanitizing USB drives, external HDDs, and secondary partitions before disposal or repurposing.

## Features

- Optionally formats the target volume before wiping.
- Performs three overwrite passes on the free space:
  1. `0x00` (zero-fill)
  2. `0xFF` (one-fill)
  3. Random data (cryptographic RNG)
- Displays target drive information and requires a confirmation phrase before proceeding.
- Blocks operations on fixed disks by default (use `-Force` to override).
- Supports NTFS and exFAT file systems.
- Validates chunk size input with `ValidateRange`.
- Requires Administrator privileges (`#Requires -RunAsAdministrator`).

## Requirements

- Windows 8+ / Windows Server 2012+ (requires the Storage module).
- PowerShell 5.1 (Windows PowerShell) or PowerShell 7+.
- Administrator privileges.

## Usage

Open PowerShell as Administrator, navigate to the script directory, and run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\SecureDiskWipe.ps1 -DriveLetter E
```

If the target is an internal fixed disk, add `-Force`:

```powershell
.\SecureDiskWipe.ps1 -DriveLetter E -Force
```

To skip formatting and only wipe existing free space:

```powershell
.\SecureDiskWipe.ps1 -DriveLetter E -SkipFormat
```

Use exFAT instead of NTFS:

```powershell
.\SecureDiskWipe.ps1 -DriveLetter E -FileSystem exFAT
```

Use quick format and a custom volume label:

```powershell
.\SecureDiskWipe.ps1 -DriveLetter E -QuickFormat -NewFileSystemLabel "CLEAN"
```

## Parameters

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `-DriveLetter` | string (required) | — | Target drive letter, e.g. `E`. |
| `-FileSystem` | NTFS / exFAT | `NTFS` | File system for the formatted volume. |
| `-NewFileSystemLabel` | string | `WIPED` | Volume label after formatting. |
| `-SkipFormat` | switch | off | Skip formatting; only wipe existing free space. |
| `-QuickFormat` | switch | off | Use quick format instead of full format. |
| `-Force` | switch | off | Allow operations on fixed (internal) disks. |
| `-ChunkMiB` | int (1–4096) | `64` | Write buffer size in MiB per I/O operation. |

## Important Notes

- **Double-check the drive letter.** The script will ask you to type a confirmation phrase (e.g. `WIPE E`) before proceeding.
- This tool is designed for HDDs, USB drives, and external disks under normal data-recovery scenarios.
- **SSD/NVMe drives:** File-level overwriting cannot guarantee all historical data is erased due to wear leveling, TRIM, over-provisioning, and controller remapping. For higher assurance, use the manufacturer's Secure Erase tool, BIOS/NVMe Secure Erase, or the Windows "Reset this PC" drive cleaning option.
- Three overwrite passes take time — larger volumes will take longer.
- The script does not wipe hidden partitions, remapped bad sectors, firmware caches, or reserved disk areas.

## Disclaimer

This is a personal data sanitization tool. Verify the target drive letter before execution. The author is not responsible for data loss caused by misuse.

## License

MIT
