param([switch]$Check)

$ErrorActionPreference = 'Stop'

$BundleName = '05cd02202827e9a0'
$OrigLine   = 'boot_package = "resource_packages/boot"'
$NewLine    = 'boot_package = "resource_packages/boot_dh"'

function Find-Contents {
    $candidates = @()

    $steam = $null
    try { $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath } catch { }
    if (-not $steam) {
        try { $steam = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction Stop).InstallPath } catch { }
    }
    if (-not $steam) {
        try { $steam = (Get-ItemProperty 'HKLM:\SOFTWARE\Valve\Steam' -ErrorAction Stop).InstallPath } catch { }
    }

    if ($steam) {
        $steam = $steam.TrimEnd('\')

        if (Test-Path -LiteralPath $steam) {
            $candidates += (Join-Path $steam 'steamapps\common\Helldivers\contents')
            $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'

            if (Test-Path -LiteralPath $vdf) {
                $raw = Get-Content -LiteralPath $vdf -Raw

                foreach ($m in [regex]::Matches($raw, '"path"\s+"([^"]+)"')) {
                    $lib = $m.Groups[1].Value.Replace('\\', '\')

                    # a library folder can sit on a drive that is not connected any more; skip it instead of failing
                    if (-not $lib -or -not (Test-Path -LiteralPath $lib)) {
                        continue
                    }

                    try {
                        $candidates += (Join-Path $lib 'steamapps\common\Helldivers\contents')
                    } catch { }
                }
            }
        }
    }

    foreach ($c in $candidates) {
        try {
            if (Test-Path -LiteralPath (Join-Path $c 'settings.ini')) { return $c }
        } catch { }
    }

    Write-Host 'Could not locate the Helldivers contents directory automatically.' -ForegroundColor Yellow
    $manual = Read-Host 'Paste the path (for example D:\Steam\steamapps\common\Helldivers\contents)'

    if ($manual) {
        $manual = $manual.Trim().Trim('"')

        try {
            if (Test-Path -LiteralPath (Join-Path $manual 'settings.ini')) { return $manual }
        } catch { }
    }

    return $null
}

$contents = Find-Contents
if (-not $contents) {
    Write-Host 'Game directory not found, revert aborted.' -ForegroundColor Red
    exit 1
}

$ini = Join-Path $contents 'settings.ini'
Write-Host "game directory: $contents"

$backups = Get-ChildItem $contents -Filter 'settings.ini.bak_dh_*' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime

if ($Check) {
    Write-Host ("backup found: " + ($(if ($backups) { $backups[-1].Name } else { 'none' })))
    Write-Host ("settings.ini now: " + ((Select-String -Path $ini -Pattern 'boot_package').Line))
    exit 0
}

if ($backups) {
    Copy-Item $backups[-1].FullName $ini -Force
    Write-Host "settings.ini restored from backup: $($backups[-1].Name)"
} else {
    $bytes = [IO.File]::ReadAllBytes($ini)
    $text  = [Text.Encoding]::UTF8.GetString($bytes)
    if ($text.Contains($NewLine)) {
        $text = $text.Replace($NewLine, $OrigLine)
        [IO.File]::WriteAllBytes($ini, [Text.Encoding]::UTF8.GetBytes($text))
        Write-Host 'settings.ini points back at resource_packages/boot'
    } else {
        Write-Host 'settings.ini does not point at boot_dh, nothing to restore.'
    }
}

if (Test-Path (Join-Path $contents $BundleName)) {
    Write-Host "($BundleName is still in the contents folder, unused; delete it by hand if you like)"
}

Write-Host ''
Write-Host 'Revert complete. Fully quit the game, then start it again.' -ForegroundColor Green
