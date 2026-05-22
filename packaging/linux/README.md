# CIM Forge — Linux packaging decision

The packaging choice for Linux is gated on **what libssh2 inside
`git2dart_binaries`' Linux `.so` actually links against**. We don't bundle
OpenSSL on Linux speculatively — distros already ship one, and bundling a
second copy risks ABI conflicts at load time.

This document captures the decision tree. Run `test/features/git/linux_libgit2_smoke_test.dart`
on a target distro (or watch the CI Linux job — its `Linux libgit2 smoke`
step runs the same test). Match its outcome against the table below.

## Decision tree

### Outcome A — smoke test passes on Ubuntu 22.04+

The prebuilt libgit2/libssh2 binaries load against the system `libssl3`
that ships with Ubuntu 22.04 / Debian 12 and forward. **System-OpenSSL
packaging is viable.**

Recommended format: **AppImage** with the system OpenSSL relied on.
Rationale:
- Single self-contained binary, no per-distro packaging.
- Honest about what the .so links — no bundled-vs-system OpenSSL conflict.
- Users on older distros (Ubuntu 20.04 with `libssl1.1`) won't be able to
  run it. Document the minimum requirement in the release notes; that's a
  smaller user impact than a bundled-OpenSSL surprise.

Alternative formats if needed:
- **deb** package (`flutter pub global activate flutter_distributor` →
  `flutter_distributor package --platform=linux --targets=deb`). Declares
  `libssl3` as a runtime dependency in `DEBIAN/control`.
- **Flatpak** with `org.freedesktop.Platform//23.08` runtime (provides
  recent OpenSSL). Sandboxed; loses access to the user's SSH agent unless
  given filesystem permission to `~/.ssh`.

### Outcome B — smoke test fails with "Failed to load dynamic library: libssl.so.1.1"

The Linux .so was built against OpenSSL 1.1 (older toolchain). Ubuntu
24.04 ships only 3.x; 22.04 ships 3.x by default; only 20.04 still has 1.1.

This is the **bundle-OpenSSL-1.1** path.

Recommended format: **AppImage with bundled libssl1.1**.
- Use linuxdeploy with the `linuxdeploy-plugin-appimage` to gather
  dependencies.
- Bundle `libssl.so.1.1` + `libcrypto.so.1.1` next to the binary.
- Document the bundle's OpenSSL version in
  `packaging/linux/third-party-licenses.txt` for audit.

Alternative if OpenSSL 1.1 vs 3 becomes painful: **Flatpak** with
`org.freedesktop.Platform//21.08` runtime (the last runtime that shipped
OpenSSL 1.1).

### Outcome C — smoke test fails for a non-OpenSSL reason

Anything else (segfault, garbled error, missing symbol unrelated to ssl) is
a `git2dart` / `git2dart_binaries` bug.

Action: file the failure trace upstream at
https://github.com/aergonaut/git2dart. Pin the dependency to the last
known-good version in `pubspec.yaml` while waiting on a fix.

## What this depends on

- `git2dart_binaries` package's Linux build pipeline. Their Linux `.so` is
  pinned to whatever OpenSSL they built against; an upstream rebuild
  against a newer OpenSSL would shift the answer.
- The runtime distro. The CI matrix runs `ubuntu-latest` (currently
  Ubuntu 24.04 with libssl3); a release for older distros may need a
  bundled-OpenSSL variant.

## When to re-run this decision

- After every `git2dart` / `git2dart_binaries` major version bump.
- When adding a new Linux target distro (e.g. RHEL).
- When the CI `Linux libgit2 smoke` step starts failing.

## What's NOT in scope here

- Code signing for Linux packages (uncommon outside enterprise distros).
- Auto-update channels (Linux users typically expect distro-package or
  Flatpak auto-update).
- Snap packaging — possible later but adds another sandboxing model to
  maintain.
