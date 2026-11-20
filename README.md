# SPR_Client_27

[简体中文](README.md) · [English](README.en.md)

中国石油大学（北京）SPR 战队的 RoboMaster 2027 自定义终端，基于[复旦大学星云 EGA 的 RM26 Custom Client](https://github.com/ClearWei/RM26_Client) 二次开发。C++ 和 Qt 源码采用 [MIT License](LICENSE)，素材来源另见[授权清单](ASSET_LICENSES.md)。

## 当前功能

- 按 `P` 选择超级对抗赛、联盟赛 3V3 或 1V1，并登录当局红方或蓝方车位。
- 指挥屏显示对应场地、红蓝阵容、基地与前哨、战场事件及工业相机。按 `M` 打开大地图。
- `Ctrl+T` 切换操作手主图传与指挥屏。按住 `Tab` 查看全屏战况。完整操作见[快捷键](docs/getting-started/keyboard-shortcuts.md)。
- 重装状态和动效跟随登录车位所属队伍。数据与可选队内同步见[配置说明](docs/getting-started/configuration.md#重装状态跨终端同步)。

## 官方依据

- [2027 高校系列赛通信协议 V1.0.0](https://bbs.robomaster.com/wiki/20204847/1969151)第 2 章定义自定义终端报文和图传接入，§2.2.7、§2.2.10 至 §2.2.12 对应安装事件和车位状态。
- [2027 超级对抗赛规则](https://bbs.robomaster.com/wiki/20204847/1969149)和[2027 高校联盟赛规则](https://bbs.robomaster.com/wiki/20204847/1969150)用于核对赛项、场地机制及重装状态。超抗重装安装条件见 §5.7.1，联盟赛 3V3 重装血量见 §3.1.1。
- 地图使用 [RoboMaster 高校赛务发布的 2027 场地图纸](https://bbs.robomaster.com/article/1970956)，SPR 制作俯视图。 [地图许可和修改说明](ASSET_LICENSES.md#spr-2027-地图)

自定义终端应按参赛赛项和当期规则接入。重装安装事件缺少公开约定的队别字段，界面仅显示能够归属本队的形态状态。

## 快速开始

手头已有 SPR Windows 运行包时，双击 `02-运行脚本/Windows/8-启动Windows自定义客户端.bat` 即可看离线界面。赛场数据和图传在接入对应赛事链路后显示。

从源码构建需要 CMake 3.21+、支持 C++17 的编译器、Qt 6 和 Protobuf。图传和正式赛场数据分别需要 FFmpeg 开发库及 Paho MQTT C。Windows 上 Qt 与依赖库须与编译器 ABI 一致。本次 Windows 构建使用 MinGW x64 和 Qt 6.8.3。

```sh
cmake -S . -B build/release -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON
cmake --build build/release --parallel 4
ctest --test-dir build/release --output-on-failure
```

依赖安装在自定义路径时，配置阶段用 `CMAKE_PREFIX_PATH` 提供 SDK 前缀。Windows 运行时需要能找到对应 Qt 插件和 DLL。构建产物使用兼容文件名 `RoboMasterClient2025`（Windows 为 `.exe`）。运行包的 Windows 入口为 `SPR2027Client.exe`。详见[开发指南](docs/rm26-client-dev-guide.md)与[运行包说明](scripts/portable/README.md)。

默认示例配置使用回环网络。联调前复制 `config.example.json` 为 `config.json`，再按现场拓扑填写。本仓库附带[独立模拟器](sim/README.md)，可用来检查协议和图传链路。模拟器沿用 2026 基线，2027 部分状态由本地测试报文验证。

## 目录与联调状态

| 目录 | 内容 |
| --- | --- |
| `src/` | Qt 客户端、协议消息和界面 |
| `resources/` | 界面、地图和音频资源 |
| `sim/` | 独立模拟器 |
| `scripts/portable/` | Windows、Linux 启动和打包工具 |
| `tests/`、`tools/release/` | 回归测试和发行检查 |
| `docs/` | 配置、快捷键、架构和协议说明 |

Windows 构建与红蓝车位切换已通过本地测试。2027 正式赛事引擎、相机图传和赛场网络待现场联调。规则及协议版本见[官方资料索引](docs/references/official-materials.md)。本仓库用于源码开发，已有便携运行包、官方安装程序和现场配置按本地交付目录管理。

项目与 DJI 或 RoboMaster 无隶属关系。问题和改动可通过本仓库 Issue 或 Pull Request 提交。 [贡献指南](CONTRIBUTING.md) · [文档索引](docs/README.md)
