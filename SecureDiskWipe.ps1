<# 
.SYNOPSIS
    Format a Windows volume, then wipe free space with three overwrite passes.

.DESCRIPTION
    This script is intended for personal data sanitization after formatting a
    removable or secondary volume. It formats the selected volume and then fills
    free space three times with temporary files using zero, 0xFF, and random
    data patterns.

    It does not wipe hidden device areas, remapped sectors, firmware caches, or
    SSD cells that are no longer mapped by the controller. For SSD/NVMe drives,
    prefer the vendor secure erase tool or Windows "Reset this PC" drive clean
    option when you need stronger assurance.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z]$')]
    [string]$DriveLetter,

    [Parameter()]
    [ValidateSet('NTFS', 'exFAT')]
    [string]$FileSystem = 'NTFS',

    [Parameter()]
    [string]$NewFileSystemLabel = 'WIPED',

    [Parameter()]
    [int]$ChunkMiB = 64,

    [Parameter()]
    [switch]$SkipFormat,

    [Parameter()]
    [switch]$QuickFormat,

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw '请使用管理员权限运行 PowerShell。'
    }
}

function Get-TargetVolume {
    param([string]$Letter)

    $normalized = $Letter.TrimEnd(':').ToUpperInvariant()
    $volume = Get-Volume -DriveLetter $normalized -ErrorAction Stop
    if ($volume.DriveType -eq 'Fixed' -and -not $Force) {
        throw "目标 $normalized`: 是固定磁盘。若确认要操作固定磁盘，请添加 -Force。"
    }

    return $volume
}

function Confirm-DestructiveAction {
    param(
        [string]$Letter,
        [Microsoft.Management.Infrastructure.CimInstance]$Volume
    )

    Write-Host ''
    Write-Host '即将执行破坏性操作：' -ForegroundColor Yellow
    Write-Host "  目标盘符: $Letter`:"
    Write-Host "  卷标: $($Volume.FileSystemLabel)"
    Write-Host "  文件系统: $($Volume.FileSystem)"
    Write-Host "  容量: $([math]::Round($Volume.Size / 1GB, 2)) GB"
    Write-Host "  是否格式化: $(-not $SkipFormat)"
    Write-Host "  擦写遍数: 3"
    Write-Host ''
    Write-Host '此操作会删除目标盘上的数据，执行后通常无法恢复。' -ForegroundColor Red

    $expected = "WIPE $Letter"
    $actual = Read-Host "请输入确认短语 [$expected]"
    if ($actual -ne $expected) {
        throw '确认短语不匹配，已取消。'
    }
}

function New-PatternBuffer {
    param(
        [ValidateSet('Zero', 'One', 'Random')]
        [string]$Pattern,
        [int]$Bytes
    )

    $buffer = [byte[]]::new($Bytes)
    switch ($Pattern) {
        'Zero' { return $buffer }
        'One' {
            [Array]::Fill[byte]($buffer, 0xFF)
            return $buffer
        }
        'Random' {
            [Security.Cryptography.RandomNumberGenerator]::Fill($buffer)
            return $buffer
        }
    }
}

function Write-WipePass {
    param(
        [string]$RootPath,
        [int]$PassNumber,
        [ValidateSet('Zero', 'One', 'Random')]
        [string]$Pattern,
        [int]$ChunkBytes
    )

    $passFile = Join-Path $RootPath ("wipe-pass-{0}.bin" -f $PassNumber)
    $buffer = New-PatternBuffer -Pattern $Pattern -Bytes $ChunkBytes
    $written = 0L

    Write-Host "第 $PassNumber 遍擦写开始，模式: $Pattern"

    try {
        $stream = [System.IO.File]::Open(
            $passFile,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )

        try {
            while ($true) {
                try {
                    $stream.Write($buffer, 0, $buffer.Length)
                    $written += $buffer.Length

                    if (($written % (1GB)) -lt $buffer.Length) {
                        Write-Host ("  已写入约 {0:N2} GB" -f ($written / 1GB))
                    }

                    if ($Pattern -eq 'Random') {
                        [Security.Cryptography.RandomNumberGenerator]::Fill($buffer)
                    }
                }
                catch [System.IO.IOException] {
                    break
                }
            }

            $stream.Flush($true)
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        if (Test-Path -LiteralPath $passFile) {
            Remove-Item -LiteralPath $passFile -Force
        }
    }

    Write-Host ("第 {0} 遍完成，写入约 {1:N2} GB" -f $PassNumber, ($written / 1GB))
}

Assert-Administrator

$drive = $DriveLetter.TrimEnd(':').ToUpperInvariant()
$volume = Get-TargetVolume -Letter $drive
Confirm-DestructiveAction -Letter $drive -Volume $volume

if (-not $SkipFormat) {
    $formatParams = @{
        DriveLetter          = $drive
        FileSystem           = $FileSystem
        NewFileSystemLabel   = $NewFileSystemLabel
        Confirm              = $false
        Force                = $true
    }

    if ($QuickFormat) {
        $formatParams.Full = $false
    }
    else {
        $formatParams.Full = $true
    }

    if ($PSCmdlet.ShouldProcess("$drive`:", "Format volume as $FileSystem")) {
        Format-Volume @formatParams | Out-Null
    }
}

$root = "$drive`:\"
$wipeDir = Join-Path $root '.secure-wipe-temp'
New-Item -ItemType Directory -Path $wipeDir -Force | Out-Null

try {
    $chunkBytes = [Math]::Max(1, $ChunkMiB) * 1MB
    Write-WipePass -RootPath $wipeDir -PassNumber 1 -Pattern Zero -ChunkBytes $chunkBytes
    Write-WipePass -RootPath $wipeDir -PassNumber 2 -Pattern One -ChunkBytes $chunkBytes
    Write-WipePass -RootPath $wipeDir -PassNumber 3 -Pattern Random -ChunkBytes $chunkBytes
}
finally {
    if (Test-Path -LiteralPath $wipeDir) {
        Remove-Item -LiteralPath $wipeDir -Recurse -Force
    }
}

Write-Host ''
Write-Host "完成：$drive`: 已格式化并完成三遍空闲空间擦写。" -ForegroundColor Green
