# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [2.1.0] - 2026-11-01

### Added
- `copilot-termux-update` CLI tool installed to `$PREFIX/bin/copilot-termux-update` for one-command updates of the setup repository, wrapper scripts, glibc hooks, and upstream Copilot engine.
- `setup.sh update` action alias.
- Added self-test check verifying `copilot-termux-update` presence and permissions (15 total checks).

### Changed
- Always enforce `--force` reinstallation of `@github/copilot-linux-arm64` during setup/updates to keep native binaries in lockstep with `@github/copilot`.
- Documented update commands in `README.md`.

## [2.0.0] - 2026-11-01

### Added
- Pure native Termux installation without `proot-distro` or `patchelf`, executing `@github/copilot-linux-arm64/copilot` directly via `$PREFIX/glibc/lib/ld-linux-aarch64.so.1`.
- Bionic shell wrapper (`$PREFIX/glibc/libexec/copilot-shell/bash`) configured as `COPILOT_BASH_PATH` and `SHELL` so shells spawned directly by Copilot's Rust engine (`runtime.node`) restore `LD_PRELOAD` (`libtermux-exec-ld-preload.so`), `TMPDIR=$PREFIX/tmp`, and `DBUS_SESSION_BUS_ADDRESS=disabled:`.
- Automatic `resolv-conf` package installation and `$PREFIX/etc/tls/certs` + `$PREFIX/tmp` directory initialization.
- Expanded 14-check `self-test` verification suite (`bash setup.sh self-test`), now also executed automatically at the end of `bash setup.sh`.

### Changed
- Removed `proot-distro` dependency and container overhead in favor of native glibc execution on Termux.
- Updated `copilot-termux-preload.cjs` to strip `LD_PRELOAD` and `LD_LIBRARY_PATH` when spawning glibc ELF binaries while preserving `libtermux-exec` for Bionic child processes.
- Updated `README.md` with technical architecture and `self-test` coverage details.

### Fixed
- Unexpected Copilot session shutdowns (`SIGTERM`/`SIGHUP`) caused by orphaned `dbus-daemon --fork` processes hitting Android's Phantom Process Killer limit when CLI tools (`glab`, `gh`, keyring checks) probed D-Bus without an active bus.
- Failed shebang execution (`#!/usr/bin/env: bad interpreter`) inside Copilot's `bash` tool caused by `runtime.node` (Rust) spawning shells via native `fork/exec` without `LD_PRELOAD`.
- `Permission denied` errors on `/tmp` during tool execution by enforcing `TMPDIR=$PREFIX/tmp`.
- Missing OS TLS trust anchor directory warning (`$PREFIX/etc/tls/certs`).
- `Segmentation fault` (exit 139) on Android 14+ / SDK 35 caused by `patchelf` corrupting Node SEA ELF headers.
