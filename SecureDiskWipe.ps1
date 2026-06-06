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

#Requires -RunAsAdministrator

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
    [ValidateRange(1, 4096)]
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
        throw 'This script requires Administrator privileges. Please run PowerShell as Administrator.'
    }
}

function Get-TargetVolume {
    param([string]$Letter)

    $normalized = $Letter.TrimEnd(':').ToUpperInvariant()
    $volume = Get-Volume -DriveLetter $normalized -ErrorAction Stop

    if ($volume.DriveType -eq 'Fixed' -and -not $Force) {
        throw "Target ${normalized}: is a fixed disk. To operate on a fixed disk, add the -Force switch."
    }

    return $volume
}

function Confirm-DestructiveAction {
    param(
        [string]$Letter,
        [Microsoft.Management.Infrastructure.CimInstance]$Volume
    )

    Write-Host ''
    Write-Host '=== DESTRUCTIVE OPERATION ===' -ForegroundColor Yellow
    Write-Host "  Target Drive: ${Letter}:"
    Write-Host "  Volume Label: $($Volume.FileSystemLabel)"
    Write-Host "  File System:  $($Volume.FileSystem)"
    Write-Host "  Capacity:     $([math]::Round($Volume.Size / 1GB, 2)) GB"
    Write-Host "  Format:       $(-not $SkipFormat)"
    Write-Host "  Wipe Passes:  3"
    Write-Host ''
    Write-Host 'This operation will DELETE ALL DATA on the target drive. Recovery is generally impossible.' -ForegroundColor Red

    $expected = "WIPE $Letter"
    $actual = Read-Host "Type confirmation phrase [$expected]"
    if ($actual -ne $expected) {
        throw 'Confirmation phrase did not match. Operation cancelled.'
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
            for ($index = 0; $index -lt $buffer.Length; $index++) {
                $buffer[$index] = 0xFF
            }
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

    $passFile = Join-Path $RootPath ("wipe-pass-{0}.tmp" -f $PassNumber)
    $buffer = New-PatternBuffer -Pattern $Pattern -Bytes $ChunkBytes
    $written = 0L

    Write-Host "Pass $PassNumber starting, pattern: $Pattern"

    try {
        $stream = [System.IO.File]::Open(
            $passFile,
            [System.IO.FileMode]::Create,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )

        try {
            while ($true) {
                try {
                    $stream.Write($buffer, 0, $buffer.Length)
                    $written += $buffer.Length

                    if (($written % (1GB)) -lt $buffer.Length) {
                        Write-Host ("  Written approx. {0:N2} GB" -f ($written / 1GB))
                    }

                    if ($Pattern -eq 'Random') {
                        [Security.Cryptography.RandomNumberGenerator]::Fill($buffer)
                    }
                }
                catch [System.IO.IOException] {
                    break
                }
            }

            $stream.Flush()
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        if (Test-Path -LiteralPath $passFile) {
            Remove-Item -LiteralPath $passFile -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host ("Pass {0} complete, wrote approx. {1:N2} GB" -f $PassNumber, ($written / 1GB))
}

# Main execution
Assert-Administrator

$drive = $DriveLetter.TrimEnd(':').ToUpperInvariant()
$volume = Get-TargetVolume -Letter $drive
Confirm-DestructiveAction -Letter $drive -Volume $volume

if (-not $SkipFormat) {
    $formatParams = @{
        DriveLetter        = $drive
        FileSystem         = $FileSystem
        NewFileSystemLabel = $NewFileSystemLabel
        Confirm            = $false
        Force              = $true
        ErrorAction        = 'Stop'
    }

    if ($QuickFormat) {
        $formatParams.Full = $false
    }
    else {
        $formatParams.Full = $true
    }

    if ($PSCmdlet.ShouldProcess("${drive}:", "Format volume as $FileSystem")) {
        try {
            Format-Volume @formatParams | Out-Null
            Write-Host "Volume ${drive}: formatted as $FileSystem." -ForegroundColor Green
        }
        catch {
            throw "Failed to format volume ${drive}:. $_"
        }
    }
}
else {
    Write-Host 'Skipping format as requested (-SkipFormat).' -ForegroundColor Yellow
}

$root = "${drive}:\"
$wipeDir = Join-Path $root '.secure-wipe-temp'

try {
    $null = New-Item -ItemType Directory -Path $wipeDir -Force -ErrorAction Stop
}
catch {
    throw "Failed to create temporary directory on ${drive}:. Check that the drive is accessible. Error: $_"
}

try {
    $chunkBytes = [Math]::Max(1, $ChunkMiB) * 1MB
    Write-WipePass -RootPath $wipeDir -PassNumber 1 -Pattern Zero  -ChunkBytes $chunkBytes
    Write-WipePass -RootPath $wipeDir -PassNumber 2 -Pattern One   -ChunkBytes $chunkBytes
    Write-WipePass -RootPath $wipeDir -PassNumber 3 -Pattern Random -ChunkBytes $chunkBytes
}
finally {
    if (Test-Path -LiteralPath $wipeDir) {
        Remove-Item -LiteralPath $wipeDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host "Done: ${drive}: formatted and free space wiped with three passes." -ForegroundColor Green
