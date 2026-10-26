param(
    [string]$Contents = 'E:\Steam\steamapps\common\Helldivers\contents',
    [string]$Extra = '',
    [string]$PackName = 'dive_harder_pack',
    [switch]$NoInstall,
    [switch]$NoZip
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root 'dist'

$pack = Join-Path $dist $PackName
$zip  = Join-Path $dist ($PackName + '.zip')

$BundleName = '05cd02202827e9a0'          # murmur64a("resource_packages/boot_dh")
$Vanilla9cfSha = '72BEBEC1C173B046B03A933EF27860BEDDECA068A575D267FBAEB2122FFFBCD4'
$Qol9cfSha     = 'C49E4597917682C4683F5062CCBC7D54992005120D994CF965E9AA73B735473D'

# 1) build
$buildArgs = @((Join-Path $root 'tools\build.py'), '--contents', $Contents)
if ($Extra) { $buildArgs += @('--extra', $Extra) }
Write-Host ('build: ' + ($buildArgs -join ' '))

python @buildArgs
if ($LASTEXITCODE -ne 0) { throw 'build.py failed' }

$vanilla = (Get-FileHash (Join-Path $dist 'dive_harder_vanilla.bin') -Algorithm SHA256).Hash
$qolPath = Join-Path $dist 'dive_harder_qol.bin'
$qol = if (Test-Path $qolPath) { (Get-FileHash $qolPath -Algorithm SHA256).Hash } else { $null }
Write-Host "vanilla = $vanilla"
Write-Host "qol     = $qol"

# 2) assemble the release directory
if (Test-Path $pack) { Remove-Item $pack -Recurse -Force }
New-Item -ItemType Directory -Path $pack -Force | Out-Null

Copy-Item (Join-Path $root 'installer\install.bat') $pack -Force
Copy-Item (Join-Path $root 'installer\revert.bat') $pack -Force
Copy-Item (Join-Path $root 'installer\revert.ps1') $pack -Force
Copy-Item (Join-Path $root 'installer\install.ps1') $pack -Force
Copy-Item (Join-Path $root 'installer\INSTALL.txt') $pack -Force
Copy-Item (Join-Path $dist 'dive_harder_vanilla.bin') $pack -Force
if ($qol) { Copy-Item $qolPath $pack -Force }

# 3) write the checksum lines ( $VanillaBuild / $QolBuild in install.ps1 )
$enc = New-Object Text.UTF8Encoding($false)
$ps1 = Get-Content (Join-Path $pack 'install.ps1') -Raw
$ps1 = $ps1 -replace "(?m)^\`$VanillaBuild\s*=\s*'[0-9A-F]*'", "`$VanillaBuild  = '$vanilla'"
if ($qol) {
    $ps1 = $ps1 -replace "(?m)^\`$QolBuild\s*=\s*'[0-9A-F]*'", "`$QolBuild      = '$qol'"
}
[IO.File]::WriteAllBytes((Join-Path $pack 'install.ps1'), [byte[]](0xEF, 0xBB, 0xBF) + $enc.GetBytes($ps1))

$doc = Get-Content (Join-Path $pack 'INSTALL.txt') -Raw
$doc = $doc -replace 'dive_harder_vanilla\.bin\s*= [0-9A-F]+', "dive_harder_vanilla.bin = $vanilla"
if ($qol) {
    $doc = $doc -replace 'dive_harder_qol\.bin\s*= [0-9A-F]+', "dive_harder_qol.bin     = $qol"
}
[IO.File]::WriteAllBytes((Join-Path $pack 'INSTALL.txt'), [byte[]](0xEF, 0xBB, 0xBF) + $enc.GetBytes($doc))

# 4) install into the local game (optional)
if (-not $NoInstall) {
    $dst = Join-Path $Contents $BundleName
    $cf = Join-Path $Contents '9cf71054ea26dddf'

    if (-not (Test-Path $cf)) { throw "$cf not found, wrong game directory?" }

    $cfHash = (Get-FileHash $cf -Algorithm SHA256).Hash

    if ($cfHash -eq $Qol9cfSha) {
        if (-not $qol) { throw 'QoL detected, but this build did not produce dive_harder_qol.bin' }
        Copy-Item $qolPath $dst -Force
    } elseif ($cfHash -eq $Vanilla9cfSha) {
        Copy-Item (Join-Path $dist 'dive_harder_vanilla.bin') $dst -Force
    } else {
        throw "unknown 9cf version: $cfHash (a dedicated package has to be built)"
    }

    $iniPath = Join-Path $Contents 'settings.ini'
    $ini = Get-Content $iniPath -Raw
    if ($ini -notmatch 'boot_package\s*=\s*"resource_packages/boot_dh"') {
        Copy-Item $iniPath "$iniPath.bak_dh_$(Get-Date -Format yyyyMMdd_HHmmss)" -Force
        $ini = $ini -replace 'boot_package\s*=\s*"[^"]*"', 'boot_package = "resource_packages/boot_dh"'
        [IO.File]::WriteAllBytes($iniPath, $enc.GetBytes($ini))
    }
    Write-Host "installed $dst"
}

# 5) zip
if (-not $NoZip) {
    Remove-Item $zip -ErrorAction SilentlyContinue
    Compress-Archive -Path (Join-Path $pack '*') -DestinationPath $zip -CompressionLevel Optimal
    Write-Host ("zip: {0} ({1:N0} bytes)" -f $zip, (Get-Item $zip).Length)
}

Write-Host ''
Write-Host 'release directory:' $pack
