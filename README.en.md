# SPR_Client_27

[简体中文](README.md) · [English](README.en.md)

SPR's RoboMaster 2027 custom terminal, developed from [Fudan EGA's RM26 Custom Client](https://github.com/ClearWei/RM26_Client). The C++ and Qt source is available under the [MIT License](LICENSE). See the [asset register](ASSET_LICENSES.md) for media provenance.

## Current client

- Press `P` to choose RMUC, RMUL 3v3 or RMUL 1v1 and select the assigned red or blue seat.
- The command screen combines the arena map, both rosters, objectives, match events and the industrial camera preview. Press `M` for the expanded map.
- Use `Ctrl+T` to switch between the pilot video and command views. Hold `Tab` for match statistics. Heavy robot effects follow the logged-in team. [Keyboard shortcuts](docs/getting-started/keyboard-shortcuts.md)

## Official references

The 2027 implementation references the [communication protocol](https://bbs.robomaster.com/wiki/20204847/1969151), the [RMUC rulebook](https://bbs.robomaster.com/wiki/20204847/1969149) and the [RMUL rulebook](https://bbs.robomaster.com/wiki/20204847/1969150). The arena images are derived from the [official 2027 field drawings](https://bbs.robomaster.com/article/1970956), under the terms recorded in the [asset register](ASSET_LICENSES.md).

## Quick start

Use CMake 3.21+, a C++17 compiler, Qt 6 and Protobuf. Add FFmpeg development libraries for video and Paho MQTT C for match telemetry. The Windows build was tested with MinGW x64 and Qt 6.8.3.

```sh
cmake -S . -B build/release -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON
cmake --build build/release --parallel 4
ctest --test-dir build/release --output-on-failure
```

Add SDK locations to `CMAKE_PREFIX_PATH` when needed. The CMake executable uses the compatibility name `RoboMasterClient2025` (`.exe` on Windows). An existing SPR Windows runtime kit launches `SPR2027Client.exe` through its custom-client launcher.

Copy `config.example.json` to `config.json` to configure a local connection. The [simulator](sim/README.md) remains a standalone 2026-baseline test source. Local tests cover selected 2027 status and UI behavior. Integration with the 2027 field engine and video hardware is pending.

This repository contains sources, game assets and build scripts. The Windows runtime kit, official installers and venue configuration are managed outside Git. [Configuration](docs/getting-started/configuration.md) · [Documentation](docs/README.md) · [Portable tools](scripts/portable/README.md)
