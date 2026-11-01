#!/bin/bash

# GitHub Copilot CLI Setup for Termux (Pure Native - No PRoot)
#
# Since v1.0.48, Copilot CLI ships a self-contained Node.js Single Executable
# Application (SEA) binary (@github/copilot-linux-arm64/copilot) and native
# Rust addons (runtime.node, cli-native.node, copilot-runtime) compiled against
# glibc, which is incompatible with Android's Bionic libc.
#
# This setup runs Copilot CLI purely in Termux (no proot, no patchelf corruption,
# no separate Node.js download) using Termux's native glibc dynamic linker
# (ld-linux-aarch64.so.1) directly on @github/copilot-linux-arm64/copilot.
#
# Usage:
#   bash setup.sh              # Install Copilot CLI
#   bash setup.sh update       # Update Copilot CLI and setup components
#   bash setup.sh self-test    # Verify existing installation
#
# Based on: https://github.com/github/copilot-cli/issues/3333

# Ensure running under Termux
if [ -z "${TERMUX_VERSION:-}" ]; then
  echo "Error: This setup script must be run inside Termux (TERMUX_VERSION not set). Exiting." >&2
  exit 1
fi

set -e  # Exit on error
set -u  # Exit on undefined variable

# Only aarch64 is supported
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
  echo "Error: Only aarch64/arm64 is supported. Detected: $ARCH" >&2
  exit 1
fi

# Configuration
SETUP_VERSION="2.2.0"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
GLIBC_PREFIX="${PREFIX}/glibc"
LD_SO="${GLIBC_PREFIX}/lib/ld-linux-aarch64.so.1"
PRELOAD_CJS="${GLIBC_PREFIX}/etc/copilot-termux-preload.cjs"
SHELL_WRAPPER="${GLIBC_PREFIX}/libexec/copilot-shell/bash"
PLATFORM_PKG="@github/copilot-linux-arm64"
COPILOT_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/copilot/pkg/linux-arm64"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# HELPER FUNCTIONS
################################################################################

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_step() {
    echo ""
    echo -e "${GREEN}▶${NC} ${BLUE}$1${NC}"
    echo ""
}

ensure_pkg() {
  local pkgname="$1"
  local check_cmd="${2:-}"

  if [ -n "$check_cmd" ]; then
    if command -v "$check_cmd" >/dev/null 2>&1; then
      print_info "$pkgname already available"
      return 0
    fi
  fi

  print_info "Installing $pkgname..."
  if pkg install -y "$pkgname"; then
    print_success "$pkgname installed"
  else
    print_error "Failed to install $pkgname"
    return 1
  fi
}

################################################################################
# INSTALLATION (PURE TERMUX NATIVE)
################################################################################

install_native() {
    print_header "GitHub Copilot CLI on Termux (Pure Native - No PRoot)"

    echo "This script installs GitHub Copilot CLI purely in Termux using"
    echo "Termux's native glibc dynamic linker (no proot container required)."
    echo ""
    echo "What it does:"
    echo "  1. Installs glibc-runner and required Termux packages"
    echo "  2. Installs @github/copilot and @github/copilot-linux-arm64 via npm"
    echo "  3. Extracts the bundled Copilot SEA runtime into ~/.cache/copilot"
    echo "  4. Installs Termux runtime preload hook and launcher at \$PREFIX/bin/copilot"
    echo ""
    echo "Architecture: $ARCH"
    echo "Termux: ${TERMUX_VERSION:-unknown}"
    echo ""

    if [ -z "${NONINTERACTIVE:-}" ] && [ -t 0 ]; then
        read -p "Press Enter to continue or Ctrl+C to abort..."
    fi

    ############################################################################
    # Step 1: Install system dependencies
    ############################################################################

    print_step "Step 1/5: Installing system dependencies"

    SOURCES_LIST="$PREFIX/etc/apt/sources.list"
    if grep -q "grimler.se/termux-glibc" "$SOURCES_LIST" 2>/dev/null; then
        print_info "Removing stale grimler.se glibc repo..."
        sed -i '/grimler\.se\/termux-glibc/d' "$SOURCES_LIST"
    fi

    pkg update -y || print_warning "pkg update had issues, continuing..."
    pkg install -y termux-keyring 2>/dev/null || true

    ensure_pkg ca-certificates
    ensure_pkg resolv-conf
    mkdir -p "$PREFIX/etc/tls/certs" "$PREFIX/tmp"
    ensure_pkg nodejs node
    ensure_pkg ripgrep rg

    # Install glibc repository
    print_info "Adding glibc repository..."
    pkg install -y glibc-repo 2>/dev/null || {
        print_warning "glibc-repo package not found in main repo, adding manually..."
        GLIBC_LIST="$PREFIX/etc/apt/sources.list.d/glibc.list"
        mkdir -p "$PREFIX/etc/apt/sources.list.d"
        cat > "$GLIBC_LIST" << 'REPO'
deb [trusted=yes] https://packages-cf.termux.dev/apt/termux-glibc/ glibc stable
REPO
        pkg update -y || true
    }

    # Install glibc-runner
    if pkg install -y glibc-runner; then
        print_success "glibc-runner installed"
    else
        print_error "Failed to install glibc-runner."
        exit 1
    fi

    # Fix permissions and verify ld.so
    chmod +x "$LD_SO" 2>/dev/null || true
    chmod +x "$GLIBC_PREFIX/bin/ld.so" 2>/dev/null || true

    if [ ! -f "$LD_SO" ]; then
        print_error "glibc dynamic linker not found at $LD_SO"
        exit 1
    fi
    print_success "glibc dynamic linker found at $LD_SO"

    ############################################################################
    # Step 2: Install Copilot CLI and platform binary
    ############################################################################

    print_step "Step 2/5: Installing @github/copilot and $PLATFORM_PKG via npm"

    if npm install -g --include=optional @github/copilot; then
        print_success "@github/copilot installed"
    else
        print_error "Failed to install @github/copilot"
        exit 1
    fi

    # Because Termux reports process.platform === "android", npm skips optional
    # dependencies targeting linux. Ensure @github/copilot-linux-arm64 is installed with --force.
    NPM_ROOT="$(npm root -g)"
    COPILOT_BIN="$NPM_ROOT/$PLATFORM_PKG/copilot"

    print_info "Ensuring platform package $PLATFORM_PKG is installed..."
    npm install -g --force "$PLATFORM_PKG" || {
        print_error "Failed to install platform package $PLATFORM_PKG"
        exit 1
    }

    if [ ! -x "$COPILOT_BIN" ]; then
        print_error "Copilot native binary not found at $COPILOT_BIN"
        exit 1
    fi
    print_success "Copilot native binary installed at $COPILOT_BIN"

    ############################################################################
    # Step 3: Create Termux runtime preload hook and shell wrapper
    ############################################################################

    print_step "Step 3/5: Creating Termux runtime preload hook and shell wrapper"

    mkdir -p "$(dirname "$SHELL_WRAPPER")"
    cat > "$SHELL_WRAPPER" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export TMPDIR="${TMPDIR:-$PREFIX/tmp}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-disabled:}"
if [ -f "$PREFIX/lib/libtermux-exec-ld-preload.so" ]; then
    export LD_PRELOAD="$PREFIX/lib/libtermux-exec-ld-preload.so"
fi
exec "$PREFIX/bin/bash" "$@"
EOF
    chmod +x "$SHELL_WRAPPER"
    print_success "Termux shell wrapper created at $SHELL_WRAPPER"

    mkdir -p "$(dirname "$PRELOAD_CJS")"
    cat > "$PRELOAD_CJS" << 'EOF'
// GitHub Copilot CLI Termux Native Preload Hook
const cp = require('node:child_process');
const fs = require('node:fs');

const PREFIX = process.env.PREFIX || '/data/data/com.termux/files/usr';
const GLIBC_PREFIX = `${PREFIX}/glibc`;
const LD_SO = `${GLIBC_PREFIX}/lib/ld-linux-aarch64.so.1`;
const GLIBC_LIB = `${GLIBC_PREFIX}/lib`;
const TERMUX_EXEC_SO = `${PREFIX}/lib/libtermux-exec-ld-preload.so`;
const BASH_BIN = `${PREFIX}/bin/bash`;
const SH_BIN = `${PREFIX}/bin/sh`;
const SHELL_WRAPPER = `${GLIBC_PREFIX}/libexec/copilot-shell/bash`;
const COPILOT_LAUNCHER = `${PREFIX}/bin/copilot`;

// 1. Point process.execPath and argv[0] to the Termux launcher
Object.defineProperty(process, 'execPath', {
  value: COPILOT_LAUNCHER,
  writable: true,
  configurable: true,
});
if (process.argv[0] && process.argv[0].includes('ld-linux-aarch64')) {
  process.argv[0] = COPILOT_LAUNCHER;
}

// 2. Ensure Termux environment defaults (TMPDIR, D-Bus keyring guard, SHELL, COPILOT_BASH_PATH)
if (!process.env.TMPDIR || process.env.TMPDIR === '/tmp') {
  process.env.TMPDIR = `${PREFIX}/tmp`;
}
if (!process.env.DBUS_SESSION_BUS_ADDRESS) {
  process.env.DBUS_SESSION_BUS_ADDRESS = 'disabled:';
}
const targetShell = fs.existsSync(SHELL_WRAPPER) ? SHELL_WRAPPER : BASH_BIN;
process.env.SHELL = targetShell;
process.env.COPILOT_BASH_PATH = targetShell;

// 3. Rewrite /bin/* and /usr/bin/* paths and wrap glibc ELF binaries in child_process
function rewriteFile(file) {
  if (typeof file !== 'string') return file;
  if (file === '/bin/bash' || file === '/usr/bin/bash') return targetShell;
  if (file === '/bin/sh' || file === '/usr/bin/sh') return SH_BIN;
  if (file.startsWith('/bin/') || file.startsWith('/usr/bin/')) {
    const candidate = `${PREFIX}/bin/${file.split('/').pop()}`;
    if (fs.existsSync(candidate)) return candidate;
  }
  return file;
}

function isGlibcElf(file) {
  if (typeof file !== 'string') return false;
  return file.endsWith('/copilot-runtime') || (file.endsWith('/copilot') && file !== COPILOT_LAUNCHER);
}

const origSpawn = cp.ChildProcess.prototype.spawn;
cp.ChildProcess.prototype.spawn = function (options) {
  if (options && typeof options === 'object') {
    if (isGlibcElf(options.file)) {
      const target = options.file;
      options.file = LD_SO;
      options.args = [LD_SO, '--library-path', GLIBC_LIB, target, ...(options.args ? options.args.slice(1) : [])];
      if (Array.isArray(options.envPairs)) {
        options.envPairs = options.envPairs.filter(
          (p) => !p.startsWith('LD_PRELOAD=') && !p.startsWith('LD_LIBRARY_PATH=')
        );
      }
    } else {
      const rewritten = rewriteFile(options.file);
      if (rewritten !== options.file) {
        if (Array.isArray(options.args) && options.args[0] === options.file) {
          options.args[0] = rewritten;
        }
        options.file = rewritten;
      }
      if (Array.isArray(options.envPairs) && fs.existsSync(TERMUX_EXEC_SO)) {
        const hasPreload = options.envPairs.some((p) => p.startsWith('LD_PRELOAD='));
        if (!hasPreload) {
          options.envPairs.push(`LD_PRELOAD=${TERMUX_EXEC_SO}`);
        }
      }
    }
  }
  return origSpawn.call(this, options);
};

const origSpawnSync = cp.spawnSync;
cp.spawnSync = function (file, args, options) {
  if (isGlibcElf(file)) {
    const actualArgs = Array.isArray(args) ? args : [];
    const actualOpts = (!Array.isArray(args) && args) ? args : options;
    return origSpawnSync.call(this, LD_SO, ['--library-path', GLIBC_LIB, file, ...actualArgs], actualOpts);
  }
  return origSpawnSync.call(this, rewriteFile(file), args, options);
};
EOF
    print_success "Preload hook created at $PRELOAD_CJS"

    ############################################################################
    # Step 4: Extract bundled package and patch index.js
    ############################################################################

    print_step "Step 4/5: Extracting bundled Copilot package"

    if env -u LD_PRELOAD -u LD_LIBRARY_PATH COPILOT_SEA_EXTRACT_ONLY=1 "$LD_SO" --library-path "$GLIBC_PREFIX/lib" "$COPILOT_BIN"; then
        print_success "Bundled package extracted to $COPILOT_CACHE_DIR"
    else
        print_error "Failed to extract bundled package from $COPILOT_BIN"
        exit 1
    fi

    for INDEX_JS in "$COPILOT_CACHE_DIR"/*/index.js; do
        if [ -f "$INDEX_JS" ] && ! grep -q "copilot-termux-preload.cjs" "$INDEX_JS"; then
            sed -i "/createRequire(import.meta.url);/a require(\"$PRELOAD_CJS\");" "$INDEX_JS"
            print_success "Injected Termux preload hook into $INDEX_JS"
        fi
    done

    ############################################################################
    # Step 5: Create copilot launcher
    ############################################################################

    print_step "Step 5/5: Creating copilot launcher"

    rm -f "$PREFIX/bin/copilot"
    cat > "$PREFIX/bin/copilot" << EOF
#!/data/data/com.termux/files/usr/bin/bash
# GitHub Copilot CLI launcher for Termux (Pure Native - No PRoot)
# Generated by copilot-termux-setup

SETUP_VERSION="$SETUP_VERSION"
PREFIX="\${PREFIX:-/data/data/com.termux/files/usr}"
GLIBC_PREFIX="\${PREFIX}/glibc"
LD_SO="\${GLIBC_PREFIX}/lib/ld-linux-aarch64.so.1"
PRELOAD_CJS="\${GLIBC_PREFIX}/etc/copilot-termux-preload.cjs"
SHELL_WRAPPER="\${GLIBC_PREFIX}/libexec/copilot-shell/bash"
COPILOT_BIN="\${PREFIX}/lib/node_modules/@github/copilot-linux-arm64/copilot"
COPILOT_CACHE_DIR="\${XDG_CACHE_HOME:-\$HOME/.cache}/copilot/pkg/linux-arm64"
CHECK_FILE="\${XDG_CACHE_HOME:-\$HOME/.cache}/copilot/setup_update_available"
LAST_CHECK="\${XDG_CACHE_HOME:-\$HOME/.cache}/copilot/last_setup_check"

# Display notice if an update was found by a previous background check
if [ -t 1 ] && [ -f "\$CHECK_FILE" ]; then
    avail_ver="\$(cat "\$CHECK_FILE" 2>/dev/null || true)"
    if [ -n "\$avail_ver" ] && [ "\$avail_ver" != "\$SETUP_VERSION" ] && [ "\$avail_ver" != "v\$SETUP_VERSION" ]; then
        echo -e "\033[1;33m⚠ Nueva versión de copilot-termux-setup disponible: \$avail_ver. Ejecuta 'copilot-termux-update' para actualizar.\033[0m" >&2
    fi
fi

# Background check for updates (non-blocking, runs at most once per 24 hours)
now=\$(date +%s 2>/dev/null || echo 0)
last=\$(stat -c %Y "\$LAST_CHECK" 2>/dev/null || echo 0)
if [ "\$((now - last))" -ge 86400 ]; then
    mkdir -p "\$(dirname "\$LAST_CHECK")"
    touch "\$LAST_CHECK"
    (
        tag=\$(curl -fsSL --connect-timeout 2 -m 4 "https://api.github.com/repos/cafeteru/copilot-termux-setup/releases/latest" 2>/dev/null | grep -o '"tag_name": *"[^"]*"' | head -n 1 | cut -d '"' -f 4)
        if [ -n "\$tag" ]; then
            clean_tag="\${tag#v}"
            if [ "\$clean_tag" != "\$SETUP_VERSION" ]; then
                echo "\$tag" > "\$CHECK_FILE"
            else
                rm -f "\$CHECK_FILE"
            fi
        fi
    ) >/dev/null 2>&1 &
fi

# Ensure any newly extracted/updated Copilot version has the Termux preload hook
if [ -d "\$COPILOT_CACHE_DIR" ]; then
    for idx in "\$COPILOT_CACHE_DIR"/*/index.js; do
        if [ -f "\$idx" ] && ! grep -q "copilot-termux-preload.cjs" "\$idx" 2>/dev/null; then
            sed -i "/createRequire(import.meta.url);/a require(\\"\$PRELOAD_CJS\\");" "\$idx" 2>/dev/null || true
        fi
    done
fi

export PREFIX="\$PREFIX"
export TMPDIR="\${TMPDIR:-\$PREFIX/tmp}"
export SSL_CERT_FILE="\$PREFIX/etc/tls/cert.pem"
export SSL_CERT_DIR="\$PREFIX/etc/tls/certs"
export NODE_EXTRA_CA_CERTS="\$PREFIX/etc/tls/cert.pem"
export DBUS_SESSION_BUS_ADDRESS="\${DBUS_SESSION_BUS_ADDRESS:-disabled:}"
export SHELL="\$SHELL_WRAPPER"
export COPILOT_BASH_PATH="\$SHELL_WRAPPER"
unset LD_PRELOAD
unset LD_LIBRARY_PATH

exec "\$LD_SO" --library-path "\$GLIBC_PREFIX/lib" "\$COPILOT_BIN" "\$@"
EOF
    chmod +x "$PREFIX/bin/copilot"
    print_success "copilot launcher created at $PREFIX/bin/copilot"

    rm -f "$PREFIX/bin/copilot-termux-update"
    cat > "$PREFIX/bin/copilot-termux-update" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -e

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
REPO_DIR="${COPILOT_TERMUX_DIR:-$HOME/copilot-termux-setup}"
RAW_SETUP_URL="https://raw.githubusercontent.com/cafeteru/copilot-termux-setup/main/setup.sh"
CHECK_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/copilot/setup_update_available"

echo "=== Updating Copilot Termux Setup ==="

export NONINTERACTIVE=1

# 1. Update installer and scripts
if [ -d "$REPO_DIR/.git" ]; then
    echo "Updating repository at $REPO_DIR..."
    git -C "$REPO_DIR" pull --ff-only origin main 2>/dev/null || {
        echo "Notice: git pull skipped or failed; running setup with current repository files" >&2
    }
    bash "$REPO_DIR/setup.sh" install
else
    echo "Downloading and running latest setup.sh from GitHub..."
    curl -fsSL "$RAW_SETUP_URL" | bash
fi

# 2. Check for Copilot CLI runtime updates
if command -v copilot >/dev/null 2>&1; then
    echo "Checking for Copilot engine updates..."
    copilot update || true
fi

# 3. Clear pending update notice
rm -f "$CHECK_FILE"

echo "=== Copilot update completed successfully! ==="
EOF
    chmod +x "$PREFIX/bin/copilot-termux-update"
    print_success "copilot-termux-update created at $PREFIX/bin/copilot-termux-update"

    ############################################################################
    # Verify
    ############################################################################

    run_self_test

    print_header "Installation Complete!"

    echo "Components installed (Pure Termux - No PRoot):"
    echo "  • @github/copilot-linux-arm64 at $COPILOT_BIN"
    echo "  • Extracted runtime at $COPILOT_CACHE_DIR"
    echo "  • Preload hook at $PRELOAD_CJS"
    echo "  • Shell wrapper at $SHELL_WRAPPER"
    echo "  • Launcher at $PREFIX/bin/copilot"
    echo "  • Updater tool at $PREFIX/bin/copilot-termux-update"
    echo ""
    echo "To update Copilot and setup components in the future, run:"
    echo "  copilot-termux-update"
    echo ""
    echo "Next steps:"
    echo "  1. Launch Copilot: copilot"
    echo "  2. Sign in: /login"
    echo "  3. Start coding with AI assistance!"
    echo ""
    print_success "Setup completed successfully!"
}

################################################################################
# SELF-TEST
################################################################################

run_self_test() {
    print_header "GitHub Copilot CLI self-test (Pure Native)"

    FAILED=0
    NPM_ROOT="$(npm root -g)"
    COPILOT_BIN="$NPM_ROOT/$PLATFORM_PKG/copilot"

    run_cmd() {
        local label="$1"
        shift
        local out
        if out="$("$@" 2>&1)"; then
            print_success "$label"
            [ -n "$out" ] && echo "    $out"
            return 0
        else
            print_error "$label"
            [ -n "$out" ] && echo "    $out"
            FAILED=$((FAILED + 1))
            return 1
        fi
    }

    run_cmd "glibc linker exists" test -f "$LD_SO"
    run_cmd "TLS cert.pem exists" test -f "$PREFIX/etc/tls/cert.pem"
    run_cmd "TLS certs directory exists" test -d "$PREFIX/etc/tls/certs"
    run_cmd "resolv.conf exists" test -f "$PREFIX/etc/resolv.conf"
    run_cmd "Termux tmp directory writable" test -w "$PREFIX/tmp"
    run_cmd "Copilot SEA binary present" test -x "$COPILOT_BIN"
    run_cmd "Preload hook present" test -f "$PRELOAD_CJS"
    run_cmd "Shell wrapper present" test -x "$SHELL_WRAPPER"
    run_cmd "Termux launcher present" test -x "$PREFIX/bin/copilot"
    run_cmd "copilot-termux-update tool present" test -x "$PREFIX/bin/copilot-termux-update"
    run_cmd "Launcher embeds background update check" grep -q "setup_update_available" "$PREFIX/bin/copilot"
    run_cmd "Shell wrapper restores LD_PRELOAD, TMPDIR and DBUS guard" \
        env -u LD_PRELOAD -u TMPDIR -u DBUS_SESSION_BUS_ADDRESS "$SHELL_WRAPPER" -c \
        '[ -n "${LD_PRELOAD:-}" ] && [ "$TMPDIR" = "'"$PREFIX"'/tmp" ] && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]'
    run_cmd "Shell wrapper executes #!/usr/bin/env shebang without parent LD_PRELOAD" \
        env -u LD_PRELOAD "$SHELL_WRAPPER" -c \
        'f=$(mktemp) && printf "#!/usr/bin/env sh\necho shebang-ok\n" > "$f" && chmod +x "$f" && out=$("$f") && rm -f "$f" && [ "$out" = "shebang-ok" ]'
    run_cmd "Preload hook rewrites /bin/sh and sets Termux env" \
        env -u TMPDIR -u DBUS_SESSION_BUS_ADDRESS PRELOAD_CJS="$PRELOAD_CJS" node -e '
            require(process.env.PRELOAD_CJS);
            const assert = require("node:assert");
            const cp = require("node:child_process");
            assert.strictEqual(process.execPath, (process.env.PREFIX || "/data/data/com.termux/files/usr") + "/bin/copilot");
            assert.ok(process.env.TMPDIR && process.env.TMPDIR.endsWith("/tmp") && process.env.TMPDIR !== "/tmp");
            assert.ok(process.env.DBUS_SESSION_BUS_ADDRESS);
            assert.ok(process.env.COPILOT_BASH_PATH.endsWith("/copilot-shell/bash"));
            const res = cp.spawnSync("/bin/sh", ["-c", "echo preload-ok"], { encoding: "utf8" });
            assert.strictEqual(res.stdout.trim(), "preload-ok");
        '
    run_cmd "copilot --binary-version runs" "$PREFIX/bin/copilot" --binary-version
    run_cmd "copilot --version runs" "$PREFIX/bin/copilot" --version

    echo ""
    if [ "$FAILED" -eq 0 ]; then
        print_success "Self-test passed"
        return 0
    else
        print_error "Self-test failed ($FAILED check(s))"
        print_info "Re-run the installer to repair: bash setup.sh"
        exit 1
    fi
}

################################################################################
# MAIN
################################################################################

ACTION="${1:-install}"

case "$ACTION" in
    install|native|run)
        install_native
        ;;
    update)
        if [ -x "$PREFIX/bin/copilot-termux-update" ]; then
            exec "$PREFIX/bin/copilot-termux-update"
        else
            install_native
        fi
        ;;
    self-test)
        run_self_test
        ;;
    *)
        echo "Usage: bash setup.sh [install|update|self-test]" >&2
        exit 1
        ;;
esac

exit 0
