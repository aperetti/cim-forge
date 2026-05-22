#requires -version 5.1
<#
.SYNOPSIS
    Copies OpenSSL 3 DLLs into a Flutter Windows release directory and
    records what was bundled.

.DESCRIPTION
    Implements the OpenSSL bundling step for the CIM Forge Windows
    installer. See packaging\windows\README.md.

    libgit2.dll (shipped by the git2dart_binaries pub package) imports
    libssh2.dll, which depends on libcrypto-3-x64.dll. Without these next
    to the executable, the application fails to start with error code 126
    on clean Windows machines.

.PARAMETER ReleaseDir
    The Flutter Windows release output directory, typically
    build\windows\x64\runner\Release.

.PARAMETER OpenSslDir
    Directory containing libcrypto-3-x64.dll, libssl-3-x64.dll, and the
    OpenSSL LICENSE/README files. Common sources:
      - C:\vcpkg\installed\x64-windows\bin
      - C:\Program Files\OpenSSL-Win64\bin
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ReleaseDir,
    [Parameter(Mandatory = $true)][string]$OpenSslDir
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ReleaseDir -PathType Container)) {
    throw "Release directory does not exist: $ReleaseDir"
}
if (-not (Test-Path -LiteralPath $OpenSslDir -PathType Container)) {
    throw "OpenSSL source directory does not exist: $OpenSslDir"
}

$requiredDlls = @('libcrypto-3-x64.dll', 'libssl-3-x64.dll')
foreach ($dll in $requiredDlls) {
    $src = Join-Path $OpenSslDir $dll
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
        throw "Missing $dll in $OpenSslDir"
    }
    $dst = Join-Path $ReleaseDir $dll
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Host "  bundled $dll -> $dst"
}

# Best-effort: copy LICENSE.txt + version metadata if present in the source.
foreach ($file in @('LICENSE.txt', 'README.txt', 'openssl-license.txt')) {
    $src = Join-Path $OpenSslDir $file
    if (Test-Path -LiteralPath $src -PathType Leaf) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $ReleaseDir "$file.openssl") -Force
    }
}

# Record what we bundled so the build is reproducible/auditable.
$manifestPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) `
                'third-party-licenses.txt'
$libcryptoVersion = (Get-Item (Join-Path $OpenSslDir 'libcrypto-3-x64.dll')).VersionInfo.FileVersion
$libsslVersion    = (Get-Item (Join-Path $OpenSslDir 'libssl-3-x64.dll')).VersionInfo.FileVersion
$timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
$manifestLine = @"
[$timestamp] OpenSSL 3 bundled from $OpenSslDir
  libcrypto-3-x64.dll: $libcryptoVersion
  libssl-3-x64.dll:    $libsslVersion
"@
Add-Content -LiteralPath $manifestPath -Value $manifestLine
Write-Host "manifest updated: $manifestPath"
