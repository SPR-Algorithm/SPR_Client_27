# SPR 客户端使用指南

本指南从 GitHub 下载开始，依次完成编译、离线打开、模拟裁判数据和现场接入。以下命令从含有 `CMakeLists.txt` 的仓库根目录执行，除非步骤注明要切换目录。

## 1. 获取源码

GitHub 的 **Code → Download ZIP** 提供源码压缩包。解压后进入含 `CMakeLists.txt` 的目录。需要后续用 Git 更新时，改用以下命令下载。

```bash
git clone https://github.com/SPR-Algorithm/SPR_Client_27.git
cd SPR_Client_27
```

仓库包含源码、地图等资源、模拟器及部分启动和打包工具。源码包没有编译好的 Windows 客户端、战队交付目录里的双击启动脚本、官方赛事引擎或 USB 驱动。手上已经有战队完整运行包的队员可以按[运行包说明](../../scripts/portable/README.md)直接运行。

## 2. 安装依赖并编译

### Windows x64，从 CMD 开始

如果你已经拿到了战队完整运行包，按[运行包说明](../../scripts/portable/README.md)双击启动。以下步骤用于从 GitHub 下载的源码，第一次做完后，日常可以直接双击源码里的启动脚本。

1. **下载源码。** 在 GitHub 点 **Code → Download ZIP**，解压。打开能看到 `CMakeLists.txt` 那一级文件夹。
2. **安装 MSYS2。** 从 [MSYS2 官网](https://www.msys2.org/)下载安装器，安装路径保持默认的 `C:\msys64`。安装器结束时如果另开了终端，可以关掉。后面的命令都在普通 CMD 执行。
3. **在源码目录打开 CMD。** 在资源管理器点地址栏，输入 `cmd` 并回车。输入 `dir CMakeLists.txt`，能列出这个文件就说明目录正确。如果你已经打开了 CMD，也可以用 `cd /d "C:\dev\SPR_Client_27"`，把引号内的路径换成自己实际的解压目录。
4. **依次粘贴以下命令，每条跑完再执行下一条。** 第一条更新 MSYS2，第二条安装编译依赖，第三条编译并打开客户端。

   ```cmd
   scripts\portable\windows\start-from-source.bat update
   scripts\portable\windows\start-from-source.bat setup
   scripts\portable\windows\start-from-source.bat build
   ```

   如果更新提示关闭 MSYS2 进程，按提示结束该次更新，再在 CMD 里重新运行 `update`，直到更新结束后再执行 `setup`。软件包装好后，下次只想打开界面时，双击 [start-from-source.bat](../../scripts/portable/windows/start-from-source.bat) 即可。源码更新后用 `build` 重新编译。脚本生成的程序在 `build/windows/RoboMasterClient2025.exe`。

MSYS2 装在其他位置时，在当前 CMD 先执行 `set "MSYS2_ROOT=D:\msys64"`，把路径换成实际目录，然后在同一窗口执行上述命令。MSYS2 软件包版本随更新变化。项目此前验证的 Windows 编译环境为 MinGW x64 与 Qt 6.8.3。

### Ubuntu 24.04 图形桌面

在终端执行以下命令安装系统依赖。Qt 6.8.3 与 CI 一致，从 [Qt 在线安装器](https://www.qt.io/download-qt-installer)选择 **Desktop gcc 64-bit**，并安装 **Qt Multimedia** 和 **Qt Serial Port**。

```bash
sudo apt update
sudo apt install -y git build-essential cmake ninja-build pkg-config \
  libgl1-mesa-dev libxcb-cursor0 libxkbcommon-x11-0 libpulse0 libasound2t64 \
  fonts-noto-cjk libabsl-dev libprotobuf-dev protobuf-compiler libpaho-mqtt-dev \
  libavcodec-dev libavformat-dev libavutil-dev libswscale-dev
```

进入源码目录后配置、编译并启动。将 `qt_prefix` 改为实际安装前缀，且从有桌面会话的终端启动。

```bash
qt_prefix="$HOME/Qt/6.8.3/gcc_64"
cmake -S . -B build/linux -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DCMAKE_PREFIX_PATH="$qt_prefix"
cmake --build build/linux --parallel 4
(cd build/linux && ./RoboMasterClient2025)
```

编译后的程序沿用兼容文件名 `RoboMasterClient2025`。构建会把配置与声音资源复制到程序目录。后续都从该目录启动，以便使用同一份本地配置。配置阶段如提示未找到 Paho MQTT 或 FFmpeg，界面仍可用于离线预览，相关通信或视频功能需要补齐依赖后重新配置和编译。

## 3. 离线打开并检查界面

1. 按上述系统对应的启动命令打开客户端。初次启动保持示例配置，地址指向本机，无需接赛事路由器。
2. 按 `P` 打开设置，选择超级对抗赛、联盟赛 3V3 或联盟赛 1V1，再选择对应车位。例如选择超抗后可登录红方 3 号或蓝方 3 号。赛项和车位的对应关系见 [README](../../README.md#赛项与车位)。
3. 确认指挥屏地图与赛项匹配。按 `Ctrl+T` 切换到主图传界面，检查顶部比赛栏仍可见。按住 `Tab` 查看全屏战况，按 `M` 查看大地图。离线时等待图传、等待雷达和血量显示 `—` 均属预期。 [完整快捷键](keyboard-shortcuts.md)

到这里已经完成客户端启动。需要看动态数据时，再继续第 4 步。

## 4. 在本地接入模拟比赛

建议首次在同一台 Ubuntu 主机运行客户端与模拟器，回环地址可直接复用。Windows 可使用 Git Bash，确保 Python 与 Mosquitto 可在该终端调用，按[模拟器说明](../../sim/README.md)准备环境。模拟器沿用 2026 协议基线，请在客户端设置里切换到 **2026 联调**。

1. Ubuntu 安装 Python 环境和 Mosquitto，再在源码根目录安装模拟器。

   ```bash
   sudo apt install -y python3 python3-venv mosquitto ffmpeg
   python3 -m venv sim/.venv
   sim/.venv/bin/python -m pip install -e sim
   ```

2. 从源码根目录启动模拟器，保持终端运行。

   ```bash
   bash sim/run_sim.sh --no-video --mqtt-host 127.0.0.1 --mqtt-port 3333 --current-robot-id 3
   ```

3. 确认客户端程序旁 `config.json` 的 `network.mqtt_broker`、`network.mqtt_port` 和车位分别与模拟器的 `127.0.0.1`、`3333`、红方 3 号一致。启动客户端，在 `P` 中选「2026 联调」与红方 3 号。
4. 浏览器打开 `http://127.0.0.1:8000`。在「一键赛事演示」点击「一键开始」，确认客户端阶段、倒计时、血量或赛事事件随模拟器变化。
5. 测试主图传时，保持协议服务运行，另开终端从源码根目录执行下方命令。把路径换成可播放的视频文件，保留客户端监听 UDP `3334`，用 `Ctrl+T` 查看主图传。测试工业相机时，在 Web 控制台的工业相机区域选择视频并开始推流，用指挥屏预览或 `Ctrl+Y` 查看。

   ```bash
   bash sim/run_sim.sh --video-only --video-file /path/to/demo.mp4 --target-ip 127.0.0.1
   ```

## 5. 切换到官方赛事环境

1. 在客户端设备上保留已验证可运行的构建。按本场赛项从官方渠道准备赛事引擎与官方选手端，并按对应说明安装官方图传驱动。在官方选手端登录本场车位，先验证官方软件有比赛数据和主图传。 [官方资料索引](../references/official-materials.md)
2. 用有线网络按现场分配设置本机地址及掩码。记录原有网卡配置以便恢复。接入前以当场官方说明确认 Broker 地址、端口和主图传目标。
3. 退出 SPR 客户端，编辑可执行文件旁的 `config.json`。缺少文件时从仓库的 `config.example.json` 复制。2027 档填写 `competition.profile`、`competition.mqtt_broker` 和 `competition.mqtt_port`。主图传端口同时写入 `network.video_port` 和 `video.stream_url`，模板为 `udp://0.0.0.0:3334`。工业相机复用赛事 MQTT，前提是该车位有对应数据源。 [配置说明](configuration.md)
4. 按第 2 步的启动方式重新打开。在 `P` 中选择同一赛项和车位，先确认比赛阶段与计时和官方端一致，再按 `Ctrl+T` 确认主图传。需要工业相机时单独核对该画面。
5. 联调结束后关闭客户端，恢复联调前的网卡设置。2027 正式赛场环境仍待实机验证，联调记录建议包含赛项、车位、软件版本和通过的链路。

## 常见问题

| 表现 | 检查顺序 |
| --- | --- |
| CMake 找不到 Qt、Protobuf 或 Abseil | 检查 SDK 路径与所选编译器；若换过工具链，用新的 `build/` 子目录重新配置。 |
| Windows 启动时提示缺 DLL 或 Qt platform plugin | 用本节提供的脚本启动，它会为本次运行设置依赖目录。若仍报错，检查 MSYS2 安装路径和 setup 步骤。 |
| 程序能打开但没有比赛数据 | 先查 CMake 是否启用 MQTT，再核对当前协议档位、Broker 地址、端口和车位。 |
| 有比赛数据但主图传黑屏 | 先确认视频源已出图，核对发送目的 IP、UDP 端口、客户端防火墙与 FFmpeg 解码支持。 |
| 主图传正常但工业相机等待 | 检查是否有对应车位的 MQTT `CustomByteBlock` 视频源。 |
