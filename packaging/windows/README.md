# CIM Forge — Windows installer build

This directory holds the reproducible recipe for producing a Windows
installer. It does **not** publish anything; it only documents the steps so
any developer (or a CI runner with the right secrets) can build a release.

## Prerequisites

1. **Flutter 3.35.7 stable** on PATH (matches CI). Verify with
   `flutter --version`.
2. **Inno Setup 6** (the installer tooling). Default install path
   `C:\Program Files (x86)\Inno Setup 6\ISCC.exe` is assumed by the
   scripts below.
3. **OpenSSL 3 DLLs** — see [§ OpenSSL bundling](#openssl-bundling) below.
   These are the deployment finding from TR-9.2: `libgit2.dll` (shipped by
   `git2dart_binaries`) imports `libssh2.dll`, which in turn needs
   `libcrypto-3-x64.dll`. Without these next to the executable on a clean
   Windows machine, every git operation fails with `error code 126`.
4. (Release only) An Authenticode code-signing certificate accessible by
   `signtool.exe`. Without signing, SmartScreen will warn on first run.

## Build steps

```powershell
# From the repo root.
flutter build windows --release

# Copy bundled DLLs (OpenSSL 3) next to cim_forge.exe.
.\packaging\windows\bundle-openssl.ps1 `
    -ReleaseDir build\windows\x64\runner\Release `
    -OpenSslDir C:\path\to\OpenSSL-Win64\bin

# Run Inno Setup to produce the installer.
& 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe' `
    /Qp `
    "/DCIM_FORGE_VERSION=$(git describe --tags --always)" `
    packaging\windows\cim-forge.iss
```

The installer ends up at `packaging\windows\dist\cim-forge-<version>.exe`.

## OpenSSL bundling

`git2dart_binaries 1.10.3` ships `libgit2.dll` + `libssh2.dll` for Windows
but **does not ship** the OpenSSL 3 DLLs the latter depends on:

* `libcrypto-3-x64.dll`
* `libssl-3-x64.dll`

The dev machine probably has them because Git for Windows installs them
under `C:\Program Files\Git\mingw64\bin\` — but you can't assume your users
have Git for Windows. Two acceptable sources for the installer bundle:

1. **vcpkg** (`vcpkg install openssl:x64-windows`) → DLLs land in
   `<vcpkg>\installed\x64-windows\bin\`.
2. **Shining Light Productions "Win64 OpenSSL"** binary distribution
   (https://slproweb.com/products/Win32OpenSSL.html). The "Light" 64-bit
   build is sufficient.

In both cases, record the upstream version + checksum + license in
`packaging\windows\third-party-licenses.txt` and commit that file. The
OpenSSL license is Apache-2.0 (since OpenSSL 3.0) which is compatible with
redistribution.

## What `bundle-openssl.ps1` does

It copies exactly four files into the release directory:

```
libcrypto-3-x64.dll
libssl-3-x64.dll
LICENSE.openssl  (renamed from the OpenSSL distribution)
README.openssl   (renamed from the OpenSSL distribution)
```

Plus it appends a manifest line to
`packaging\windows\third-party-licenses.txt` recording the OpenSSL version
that was bundled so the installer is bit-reproducible.

## Linux packaging

Deferred — gated on a Linux smoke test that confirms what
`git2dart_binaries`' Linux `.so` links against. See the milestone plan,
M8 risk #2.
