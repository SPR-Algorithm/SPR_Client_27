# SPR 客户端迁移与验证记录

2026-11-20 将当前 SPR 源码整理到独立的 `SPR_Client_27` 工作区。原有本地运行包、官方程序、安装器、构建缓存和现场配置继续由本地交付目录管理。新工作区从 `CMakeLists.txt` 开始配置，在自己的 `build/` 目录生成产物。

Windows 验证环境为 MinGW x64、Qt 6.8.3、Protobuf 3.21.12、Paho MQTT C 和 FFmpeg 8.1。验收项目包括原生编译、QML、C++ 回归和便携脚本。2027 现场引擎、真实图传、比赛网络和 Linux 桌面出图仍待联调。

- [源码构建和运行](../../README.md#快速开始)
- [本地运行包和网络还原](../../scripts/portable/README.md)
- [配置与重装数据边界](../getting-started/configuration.md)
