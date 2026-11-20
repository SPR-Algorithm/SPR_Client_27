#!/usr/bin/env bash
# Run on the Linux client locally, or via SSH as the SAME desktop user.
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(cd "$HERE/../../.." && pwd)"
if [[ -f "$SOURCE_ROOT/CMakeLists.txt" ]]; then
    ROOT="${RM26_ROOT:-$SOURCE_ROOT}"
else
    ROOT="${RM26_ROOT:-$HOME/RM26_Client}"
fi
DEFAULT_BIN="$ROOT/build/RoboMasterClient2025"
[[ ! -x "$ROOT/build-portable/RoboMasterClient2025" ]] || DEFAULT_BIN="$ROOT/build-portable/RoboMasterClient2025"
BIN="${RM26_BINARY:-$DEFAULT_BIN}"
ACTION="${1:---background}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/rm26-client"
mkdir -p "$STATE"
PIDFILE="$STATE/client.pid"
LOG="$STATE/client.log"

running() {
    [[ -r "$PIDFILE" ]] || return 1
    read -r pid < "$PIDFILE"
    [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/exe" ]] || return 1
    [[ "$(readlink -f "/proc/$pid/exe")" == "$(readlink -f "$BIN")" ]]
}

case "$ACTION" in
    --status)
        if running; then echo "Running: PID=$pid"; else echo 'Not running (launcher-managed process)'; fi
        echo "Binary: $BIN"; echo "Log: $LOG"; exit 0 ;;
    --stop|--restart)
        if running; then
            kill "$pid"
            for _ in {1..20}; do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
            if kill -0 "$pid" 2>/dev/null; then echo 'Still shutting down; no second instance started.' >&2; exit 1; fi
        fi
        [[ "$ACTION" == '--stop' ]] && exit 0
        ACTION='--background' ;;
    --background|--foreground|--check) ;;
    *) echo "Usage: $0 [--background|--foreground|--restart|--stop|--status|--check]"; exit 2 ;;
esac

[[ -x "$BIN" ]] || { echo "Executable missing: $BIN. Build the client on this Linux machine first." >&2; exit 1; }
[[ -f "$(dirname "$BIN")/config.json" ]] || { echo "Missing config.json next to $BIN" >&2; exit 1; }
if [[ -f "$(dirname "$BIN")/qt-prefix.txt" ]]; then
    read -r qt_prefix < "$(dirname "$BIN")/qt-prefix.txt"
    if [[ ! -d "$qt_prefix/lib" && -d "$ROOT/.dependencies/Qt/6.8.3/gcc_64/lib" ]]; then
        qt_prefix="$ROOT/.dependencies/Qt/6.8.3/gcc_64"
    fi
    export LD_LIBRARY_PATH="$qt_prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

# Reuse the logged-in desktop's real display/authentication, never assume a Windows user/NUC address.
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    for candidate in $(pgrep -u "$(id -u)" -x 'gnome-shell|plasmashell|xfce4-session' || true); do
        [[ -r "/proc/$candidate/environ" ]] || continue
        while IFS= read -r item; do
            case "$item" in DISPLAY=*|XAUTHORITY=*|XDG_RUNTIME_DIR=*|WAYLAND_DISPLAY=*|DBUS_SESSION_BUS_ADDRESS=*) export "$item" ;; esac
        done < <(tr '\0' '\n' < "/proc/$candidate/environ")
        [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && break
    done
fi
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" && -S /tmp/.X11-unix/X0 ]]; then export DISPLAY=:0; fi
if [[ -z "${XAUTHORITY:-}" && -f "$HOME/.Xauthority" ]]; then export XAUTHORITY="$HOME/.Xauthority"; fi
if [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    echo 'No logged-in desktop found. Log in on the Linux display first; SSH alone cannot create a desktop.' >&2; exit 1
fi
if [[ -n "${DISPLAY:-}" ]] && command -v xdpyinfo >/dev/null; then
    xdpyinfo >/dev/null 2>&1 || { echo 'X display authorization failed. Run this script from the desktop terminal.' >&2; exit 1; }
fi
if command -v ldd >/dev/null && ldd "$BIN" | grep -q 'not found'; then
    ldd "$BIN" | grep 'not found' >&2
    exit 1
fi
export RM_START_VIEW="${RM_START_VIEW:-video}"
export RM_RUNTIME_LOG_STDERR=1
if [[ "$ACTION" == '--check' ]]; then
    echo "Ready: $BIN; DISPLAY=${DISPLAY:-wayland}; initial view=$RM_START_VIEW"
    exit 0
fi
if running; then echo "Already running: PID=$pid"; exit 0; fi
if [[ "$ACTION" == '--background' ]]; then
    nohup bash "$HERE/rm26-client.sh" --foreground </dev/null >>"$LOG" 2>&1 &
    for _ in {1..25}; do
        if running; then
            sleep 1
            running || { tail -n 15 "$LOG" >&2; exit 1; }
            echo "Started: PID=$pid; log=$LOG"
            exit 0
        fi
        sleep 0.2
    done
    tail -n 15 "$LOG" >&2
    exit 1
fi
# The executable inherits the lock FD. No broad pkill -f (which used to kill the SSH shell itself).
exec 9>"$STATE/client.lock"
flock -n 9 || { echo 'Another launcher is running.' >&2; exit 1; }
cd -- "$(dirname -- "$BIN")"
echo "$$" > "$PIDFILE"
exec "$BIN"
