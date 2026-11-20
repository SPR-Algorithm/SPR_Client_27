#!/usr/bin/env bash
# First-time setup on Ubuntu 22.04/24.04 x86_64; never run the whole script as root.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
RELEASE_ROOT="$(cd "$ROOT/../.." && pwd)"
[[ $(id -u) -ne 0 ]] || { echo 'Run as your desktop user, without sudo. Individual apt operations will request sudo.' >&2; exit 1; }
. /etc/os-release
[[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" =~ ^(22\.04|24\.04)$ && $(uname -m) == x86_64 ]] || {
    echo 'This installer supports Ubuntu 22.04/24.04 x86_64. See the project guide for other systems.' >&2; exit 1;
}
DEPS="$ROOT/.dependencies"
mkdir -p "$DEPS"
LOG="$DEPS/install.log"
exec > >(tee -a "$LOG") 2>&1
echo "Project: $ROOT"
echo "Installing build dependencies; log: $LOG"
sudo apt-get update
sudo apt-get install -y --no-install-recommends build-essential cmake ninja-build pkg-config \
    python3 python3-venv curl ca-certificates libabsl-dev libpaho-mqtt-dev \
    protobuf-compiler libprotobuf-dev libavcodec-dev libavformat-dev libavutil-dev libswscale-dev \
    libgl1-mesa-dev libxkbcommon-x11-0 libxcb-cursor0 libxcb-icccm4 libxcb-image0 \
    libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 libxcb-shape0 libxcb-shm0 \
    libxcb-sync1 libxcb-util1 libxcb-xfixes0 libxcb-xinerama0 libxcb-xkb1 \
    libfontconfig1 libdbus-1-3 fonts-noto-cjk x11-utils

QT="${RM_QT_PREFIX:-$DEPS/Qt/6.8.3/gcc_64}"
if [[ ! -f "$QT/lib/cmake/Qt6Quick/Qt6QuickConfig.cmake" || ! -f "$QT/lib/cmake/Qt6Multimedia/Qt6MultimediaConfig.cmake" || ! -f "$QT/lib/cmake/Qt6SerialPort/Qt6SerialPortConfig.cmake" ]]; then
    python3 -m venv "$DEPS/aqt"
    "$DEPS/aqt/bin/python" -m pip install aqtinstall
    "$DEPS/aqt/bin/aqt" install-qt linux desktop 6.8.3 linux_gcc_64 \
        -O "$DEPS/Qt" -m qtmultimedia qtserialport \
        -b "${RM_QT_MIRROR:-https://download.qt.io}" --timeout 60
    QT="$DEPS/Qt/6.8.3/gcc_64"
fi
PREFIXES="$QT"
if ! protoc --version | python3 -c 'import sys; v=tuple(map(int,sys.stdin.read().split()[-1].split("."))); sys.exit(0 if v >= (3,15) else 1)'; then
    PB="$DEPS/protobuf"
    if [[ ! -x "$PB/bin/protoc" ]]; then
        ARCHIVE="$ROOT/scripts/portable/vendor/protobuf-cpp-3.21.12.tar.gz"
        if [[ -f "$RELEASE_ROOT/05-安装包/Linux/protobuf-cpp-3.21.12.tar.gz" ]]; then
            ARCHIVE="$RELEASE_ROOT/05-安装包/Linux/protobuf-cpp-3.21.12.tar.gz"
        fi
        [[ -f "$ARCHIVE" ]] || { echo "Bundled source missing: $ARCHIVE. Use the complete release ZIP." >&2; exit 1; }
        (cd "$(dirname "$ARCHIVE")" && sha256sum -c SHA256SUMS)
        mkdir -p "$DEPS/source"
        tar -xzf "$ARCHIVE" -C "$DEPS/source"
        cmake -S "$DEPS/source/protobuf-3.21.12" -B "$DEPS/pb-build" -G Ninja \
            -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PB" \
            -DCMAKE_POSITION_INDEPENDENT_CODE=ON -Dprotobuf_BUILD_TESTS=OFF \
            -Dprotobuf_BUILD_EXAMPLES=OFF -Dprotobuf_WITH_ZLIB=OFF
        cmake --build "$DEPS/pb-build" --parallel "${RM_BUILD_JOBS:-2}"
        cmake --install "$DEPS/pb-build"
    fi
    export PATH="$PB/bin:$PATH"
    PREFIXES="$PREFIXES;$PB"
fi
cmake -S "$ROOT" -B "$ROOT/build-portable" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$PREFIXES" -DBUILD_TESTING=OFF
cmake --build "$ROOT/build-portable" --parallel "${RM_BUILD_JOBS:-2}" --target RoboMasterClient2025
if [[ ! -f "$ROOT/build-portable/config.json" ]]; then
    cp "$ROOT/config.example.json" "$ROOT/build-portable/config.json"
fi
# Only initialize the fresh build's default loopback config; never overwrite an existing field config.
python3 - "$ROOT/build-portable/config.json" "$RELEASE_ROOT/06-配置/Linux/config.example.json" <<'PY'
import json, os, sys
from pathlib import Path
p=Path(sys.argv[1])
d=json.loads(p.read_text(encoding='utf-8'))
if d.get('network', {}).get('mqtt_broker') == '127.0.0.1':
    p.with_suffix('.json.before-portable').write_bytes(p.read_bytes())
    template=Path(sys.argv[2])
    if template.is_file():
        d=json.loads(template.read_text(encoding='utf-8'))
    n=d['network']
    n.update(server_ip=os.getenv('RM_INITIAL_BROKER','127.0.0.1'),
             mqtt_broker=os.getenv('RM_INITIAL_BROKER','127.0.0.1'),
             server_port=3333, mqtt_port=3333, video_port=3334,
             client_robot_id=int(os.getenv('RM_INITIAL_ROBOT_ID','3')))
    p.write_text(json.dumps(d,ensure_ascii=False,indent=4)+'\n',encoding='utf-8')
PY
# Limit Qt library paths to this launcher's environment; do not modify shell profiles or system ldconfig.
printf '%s\n' "$QT" > "$ROOT/build-portable/qt-prefix.txt"
echo 'Build complete. Use the Linux launcher under 02-运行脚本/Linux in the delivery folder.'
echo 'Robot default: red 3; MQTT default: 127.0.0.1:3333. Match the official player robot ID.'
