# Secure Disk Wipe

一个 Windows PowerShell 磁盘格式化后三遍擦写脚本，适合个人在处理旧 U 盘、移动硬盘、备用分区前使用，主要目的是降低普通数据恢复软件找回文件的概率。

## 功能

- 可选择先格式化目标卷，再进行擦写。
- 对格式化后的空闲空间执行三遍填充：
  1. `0x00`
  2. `0xFF`
  3. 随机数据
- 操作前显示目标盘信息，并要求输入确认短语。
- 默认阻止固定磁盘操作，避免误擦系统盘或内置硬盘。
- 支持 NTFS 和 exFAT。

## 使用方法

以管理员身份打开 PowerShell，进入脚本目录后执行：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\SecureDiskWipe.ps1 -DriveLetter E
```

如果确认目标是内置固定磁盘，需要额外添加 `-Force`：

```powershell
.\SecureDiskWipe.ps1 -DriveLetter E -Force
```

如果已经手动格式化过，只想对剩余空间执行三遍擦写：

```powershell
.\SecureDiskWipe.ps1 -DriveLetter E -SkipFormat
```

使用 exFAT：

```powershell
.\SecureDiskWipe.ps1 -DriveLetter E -FileSystem exFAT
```

## 参数说明

| 参数 | 说明 |
| --- | --- |
| `-DriveLetter` | 必填。目标盘符，例如 `E`。 |
| `-FileSystem` | 格式化文件系统，支持 `NTFS` 和 `exFAT`，默认 `NTFS`。 |
| `-NewFileSystemLabel` | 格式化后的卷标，默认 `WIPED`。 |
| `-SkipFormat` | 跳过格式化，只擦写当前空闲空间。 |
| `-QuickFormat` | 使用快速格式化。未指定时使用完整格式化。 |
| `-Force` | 允许对固定磁盘执行操作。 |
| `-ChunkMiB` | 单次写入块大小，默认 `64` MiB。 |

## 使用提醒

- 请务必确认盘符。运行后脚本会要求输入类似 `WIPE E` 的确认短语。
- 该脚本主要针对机械硬盘、U 盘、移动硬盘和普通恢复场景。
- 对 SSD/NVMe 来说，因为磨损均衡、TRIM、预留块和控制器映射，文件级填充擦写不能保证覆盖所有历史数据。需要更高保证时，请优先使用硬盘厂商 Secure Erase 工具、主板 BIOS/NVMe Secure Erase 功能，或 Windows 重置里的清理驱动器选项。
- 三遍擦写会占用较长时间，容量越大耗时越久。
- 脚本不会擦写隐藏分区、坏块重映射区域、固件缓存或磁盘保留区域。

## 免责声明

本工具是个人本机数据清理脚本。请确认目标盘符后再执行，作者不对误操作导致的数据丢失负责。

## License

MIT
