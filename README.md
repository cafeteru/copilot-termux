# GitHub Copilot CLI Setup for Termux (Pure Native - No PRoot)

Setup script to install **GitHub Copilot CLI** directly on **Termux** (Android/aarch64) without PRoot or containers.

## Background

GitHub Copilot CLI ships a self-contained Node.js Single Executable Application (`@github/copilot-linux-arm64/copilot`) and native Rust addons (`runtime.node`, `cli-native.node`, `copilot-runtime`) compiled against **glibc**, which is incompatible with Android's Bionic libc.

Why earlier approaches failed on modern Android (Android 14/15+):
1. **ELF corruption with `patchelf`:** Running `patchelf` on Node/SEA binaries corrupts ELF program headers (`PHDR`), causing `Segmentation fault` (exit 139) on Android 14+.
2. **Bionic `LD_PRELOAD` vs Rust subprocesses:** Termux's `LD_PRELOAD` (`libtermux-exec-ld-preload.so`) is compiled for Bionic and crashes glibc processes if not unset before invoking `ld-linux-aarch64.so.1`. However, Copilot's `bash` tool is spawned directly from its Rust engine (`runtime.node`) rather than Node's `child_process`, so child shells need a Bionic shell wrapper (`$PREFIX/glibc/libexec/copilot-shell/bash`) to restore `LD_PRELOAD` (enabling `#!/usr/bin/env` and `/bin/sh` shebangs) without leaking it into glibc binaries.
3. **Android Phantom Process Killer & D-Bus keyring leaks:** Without a D-Bus session guard, CLI tools (`gh`, `glab`, keyring probes) auto-spawn orphaned `dbus-daemon --fork` processes on every invocation, hitting Android's 32-child phantom process limit and terminating the Copilot session mid-turn.
4. **Termux paths & DNS:** Android lacks a writable `/tmp`, `/etc/resolv.conf`, and standard `/etc/ssl` paths; Copilot requires `TMPDIR=$PREFIX/tmp`, `resolv-conf` (`$PREFIX/etc/resolv.conf`), and `$PREFIX/etc/tls/cert.pem` + `$PREFIX/etc/tls/certs`.
5. **Termux touch scrolling (`DECSET 1003` vs `1002`):** Copilot CLI enables mouse tracking with `MOUSE_ANY` (`\x1b[?1003h\x1b[?1006h`) without `DECSET 1002` (`\x1b[?1002h`). Termux's `TerminalEmulator` ignores mode `1003` and only activates mouse-wheel scroll events (`64`/`65`) when mode `1000` or `1002` is enabled; otherwise, vertical finger swipes in alternate-screen mode emit `Up`/`Down` arrow keys and cycle prompt history instead of scrolling the conversation. The preload hook injects `\x1b[?1002h` alongside `\x1b[?1003h` so touch scrolling works natively.

This script runs `@github/copilot-linux-arm64/copilot` directly via Termux's native glibc dynamic linker (`$PREFIX/glibc/lib/ld-linux-aarch64.so.1`) without `proot` and without `patchelf`.

## Requirements

- **Termux** on an **aarch64/arm64** Android device
- Internet connection

## Installation

### One-line install (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/cafeteru/copilot-termux-setup/main/setup.sh | bash
```

### Or clone and run locally

```bash
git clone https://github.com/cafeteru/copilot-termux-setup.git
cd copilot-termux-setup
bash setup.sh
```

The installer automatically runs the full 16-check `self-test` verification suite before finishing.

### Verify an existing install

You can also run the verification suite at any time without modifying the installation:

```bash
bash setup.sh self-test
```

What `self-test` checks:
- `ld-linux-aarch64.so.1`, `cert.pem`, `etc/tls/certs`, `etc/resolv.conf`, and writable `$PREFIX/tmp`
- Copilot SEA binary, Node preload hook (`copilot-termux-preload.cjs`), Bionic shell wrapper (`copilot-shell/bash`), `$PREFIX/bin/copilot` launcher (with background update check), and `copilot-termux-update` tool
- Shell wrapper restoration of `LD_PRELOAD`, `TMPDIR`, and `DBUS_SESSION_BUS_ADDRESS` when spawned from an clean-env parent (simulating `runtime.node`)
- Shebang execution (`#!/usr/bin/env sh`) through the shell wrapper
- Node preload hook `/bin/sh` path rewriting and environment setup
- `copilot --binary-version` and `copilot --version` execution

## Usage

```bash
copilot
```

On first launch, use `/login` to authenticate with your GitHub account.

When starting in an interactive terminal, the launcher automatically checks if an update is available (for upstream Copilot CLI or `copilot-termux-setup`) and prompts whether to update immediately (`¿Deseas actualizar ahora? [s/N]`). If accepted, it runs `copilot-termux-update` and restarts into the updated version.

## Updating

To update Copilot CLI and all Termux setup components in one command:

```bash
copilot-termux-update
```

Or via `setup.sh`:

```bash
bash setup.sh update
```

To check for upstream Copilot runtime updates only:

```bash
copilot update
```

See [CHANGELOG.md](CHANGELOG.md) for release history and technical details.

## License

MIT
