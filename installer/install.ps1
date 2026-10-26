param([switch]$Check)

$ErrorActionPreference = 'Stop'

$BundleName = '05cd02202827e9a0'          # murmur64a("resource_packages/boot_dh")
$TargetBoot = 'resource_packages/boot_dh'
$NewLine    = 'boot_package = "resource_packages/boot_dh"'

$Vanilla9cfSha = '72BEBEC1C173B046B03A933EF27860BEDDECA068A575D267FBAEB2122FFFBCD4'
$Qol9cfSha     = 'C49E4597917682C4683F5062CCBC7D54992005120D994CF965E9AA73B735473D'
$VanillaBuild  = '1921CBAA9A039AC9AB0350F4A6B762318C41AF43FCB8956F4A23BF067287D777'
$QolBuild      = 'F0DDA22A798FECCCED3D37C33AABC811C245679E304E6DFC1D146EA26C79F8DA'

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
        $candidates += (Join-Path $steam 'steamapps\common\Helldivers\contents')
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            $raw = Get-Content $vdf -Raw
            foreach ($m in [regex]::Matches($raw, '"path"\s+"([^"]+)"')) {
                $lib = $m.Groups[1].Value.Replace('\\', '\')
                $candidates += (Join-Path $lib 'steamapps\common\Helldivers\contents')
            }
        }
    }

    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c 'settings.ini')) { return $c }
    }

    Write-Host 'Could not locate the Helldivers contents directory automatically.' -ForegroundColor Yellow
    $manual = Read-Host 'Paste the path (for example D:\Steam\steamapps\common\Helldivers\contents)'
    if ($manual -and (Test-Path (Join-Path $manual 'settings.ini'))) { return $manual }
    return $null
}

$contents = Find-Contents
if (-not $contents) {
    Write-Host 'Game directory not found, installation aborted.' -ForegroundColor Red
    exit 1
}

$ini = Join-Path $contents 'settings.ini'
$dst = Join-Path $contents $BundleName
$cf  = Join-Path $contents '9cf71054ea26dddf'

if (-not (Test-Path $cf)) {
    Write-Host '9cf71054ea26dddf is missing, the game files are incomplete, installation aborted.' -ForegroundColor Red
    exit 1
}

$cfHash = (Get-FileHash $cf -Algorithm SHA256).Hash
if ($cfHash -eq $Qol9cfSha) {
    $mode = 'QoL 0.29.2'
    $srcName = 'dive_harder_qol.bin'
    $srcSha = $QolBuild
} elseif ($cfHash -eq $Vanilla9cfSha) {
    $mode = 'vanilla (no QoL)'
    $srcName = 'dive_harder_vanilla.bin'
    $srcSha = $VanillaBuild
} else {
    Write-Host 'Unknown QoL / game version (that 9cf hash is not supported).' -ForegroundColor Red
    Write-Host "9cf SHA256 = $cfHash"
    Write-Host 'This version needs a package built for it: send 9e13b2414b41b842 and 9cf71054ea26dddf from your contents folder to the author.'
    exit 1
}

$src = Join-Path $PSScriptRoot $srcName
Write-Host "game directory: $contents"
Write-Host "base: $mode"

if ($Check) {
    Write-Host ("payload: " + $srcName)
    Write-Host ("bundle present: " + (Test-Path $dst))
    Write-Host ("settings.ini now: " + ((Select-String -Path $ini -Pattern 'boot_package').Line))
    exit 0
}

if (-not (Test-Path $src)) {
    Write-Host "$srcName is missing from the archive, installation aborted (extract the whole zip again)." -ForegroundColor Red
    exit 1
}
if ((Get-FileHash $src -Algorithm SHA256).Hash -ne $srcSha) {
    Write-Host "$srcName failed the checksum check, the file is probably damaged, installation aborted." -ForegroundColor Red
    exit 1
}

Copy-Item $src $dst -Force
if ((Get-FileHash $dst -Algorithm SHA256).Hash -ne $srcSha) {
    Write-Host 'Checksum mismatch after copying, installation aborted.' -ForegroundColor Red
    exit 1
}
Write-Host "wrote: $BundleName ($mode)"

$bytes = [IO.File]::ReadAllBytes($ini)
$text  = [Text.Encoding]::UTF8.GetString($bytes)
$pattern = '(?m)^\s*boot_package\s*=\s*"[^"]*"'
if ($text.Contains($NewLine)) {
    Write-Host 'settings.ini already points at boot_dh, nothing to change'
} elseif ($text -match $pattern) {
    $backup = "$ini.bak_dh_" + (Get-Date -Format 'yyyyMMdd_HHmmss')
    Copy-Item $ini $backup
    $text = [regex]::Replace($text, $pattern, $NewLine)
    [IO.File]::WriteAllBytes($ini, [Text.Encoding]::UTF8.GetBytes($text))
    Write-Host "settings.ini now points at boot_dh (backup: $(Split-Path $backup -Leaf))"
} else {
    Write-Host 'No boot_package line in settings.ini; edit it by hand as described in INSTALL.txt.' -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host 'Installation complete. Fully quit the game, then start it again.' -ForegroundColor Green
Write-Host 'In game: press ESC (main menu / ship / mission), one row below SETTINGS is MOD SETTINGS,' -ForegroundColor Green
Write-Host 'holding the QoL options (when QoL is installed) and the DIVE HARDER options:' -ForegroundColor Green
Write-Host '  UNLOCK DEFEATED FACTIONS / SHOW HIDDEN OBJECTIVES / ENEMY HEALTH / HUD PING / PING WINDOW' -ForegroundColor Green
Write-Host 'Move to the last row, APPLY CHANGES, and confirm (or click it) to save.' -ForegroundColor Green
Write-Host 'Press ESC / Q or click BACK to leave the page.' -ForegroundColor Green
Write-Host 'Note: the patch works by switching boot_package in settings.ini, so only one boot package can be active.' -ForegroundColor Yellow
