# GazeboSimWin

Gazebo Harmonic 的 Windows 无界面、无渲染构建方案，支持 GNU（MSYS2 UCRT64）和 MSVC（vcpkg）两套工具链。

本仓库保存固定版本清单、源码补丁和构建脚本，以 `gz-sim 8.15.0` 标识这一组 Harmonic 组件。保留物理仿真、非渲染传感器和系统插件，裁去 Gazebo GUI、Qt、OGRE、渲染组件及依赖渲染的传感器，减少最终运行包体积。原生启动器为 `gz-sim-headless.exe`，默认使用 DART，也可选用 Bullet-featherstone。

## 快速构建

在 Windows PowerShell 中克隆仓库，并创建本机配置文件：

```powershell
git clone https://github.com/coasho/GazeboSimWin.git
cd GazeboSimWin
Copy-Item patch/harmonic-8.15.0/toolchain.config.example.ps1 patch/harmonic-8.15.0/toolchain.config.ps1
notepad patch/harmonic-8.15.0/toolchain.config.ps1
```

已有本机配置时，直接编辑即可，不要再次用模板覆盖。根据安装环境修改路径后，选择一套工具链构建：

```powershell
# GNU / MSYS2 UCRT64
./patch/harmonic-8.15.0/build.cmd gnu

# 或 MSVC / vcpkg
./patch/harmonic-8.15.0/build.cmd msvc
```

脚本依次克隆固定 tag、应用补丁、准备依赖、编译安装并打包。结果位于：

```text
dist/gnu/gz-sim-harmonic-8.15.0/
dist/msvc/gz-sim-harmonic-8.15.0/
```

拷贝整个运行包目录，双击其中的 `bin/gz-sim-headless.exe` 即可启动自带的箱体下落演示。

## 配置文件怎么用

| 文件 | 用途 |
|---|---|
| `patch/harmonic-8.15.0/toolchain.config.example.ps1` | 提交到仓库的配置模板，路径仅为示例。 |
| `patch/harmonic-8.15.0/toolchain.config.ps1` | 从模板复制的本机配置，构建脚本实际读取此文件；已被 Git 忽略。 |
| `patch/harmonic-8.15.0/repos.txt` | 各源码仓库及固定 tag。Harmonic 是组件集合，各库有独立版本号。 |
| `patch/harmonic-8.15.0/msys2-packages.txt` | GNU 构建需要的 MSYS2 包清单。 |
| `patch/harmonic-8.15.0/vcpkg.json` | MSVC 第三方依赖及固定的 vcpkg baseline。 |

首次配置至少检查以下内容：

- 两套工具链都需要 Git。`Git = 'git'` 从当前 `PATH` 查找，也可以填写 Git 可执行文件的绝对路径。
- GNU：将 `Msys2Root` 改为实际 MSYS2 安装根目录，`Msys2Env` 使用已验证的 `ucrt64`。模板中的 `C:/msys64` 仅为示例；目录下必须有 `ucrt64/bin/g++.exe` 等构建工具。
- MSVC：`VsInstall = ''` 通过 `vswhere` 查找带 C++ 工具的 Visual Studio，`VcpkgRoot = ''` 使用该 VS 自带的 vcpkg。`Python` 必须改成实际 Python 3 可执行文件的绝对路径；模板中的 `C:/Python3/python.exe` 不代表已安装。
- `Jobs = 0` 按逻辑处理器数量设置并行任务数。内存紧张时，按本机资源降低并行数。
- `SourceDir`、`BuildDir`、`InstallDir`、`DistDir` 的相对路径均以仓库根目录为基准，也可填写绝对路径。

仅 `VsInstall` 和 `VcpkgRoot` 支持留空自动查找。换机器后需重新核对实际安装路径；更换编译器或依赖环境时，应使用新的构建和安装目录，避免旧缓存或不同工具链的库混用。

`toolchain.config.ps1` 只影响构建，不用于配置飞机。运行时的世界、质量、惯量、传感器噪声及插件参数由 SDF 文件配置，资源和插件搜索路径可通过环境变量设置。

完整字段解释、环境要求、分阶段构建、运行时配置及补丁维护方法见 [中文构建说明](patch/harmonic-8.15.0/README.md)。

## 验证范围

此前本地验证覆盖两套工具链构建、运行包搬移、干净 `PATH` 启动，以及 DART / Bullet-featherstone 下的箱体自由落体和落地检查。Release 运行包历史测量值：GNU 约 93.8 MiB，MSVC 约 72.2 MiB；实际大小随依赖和构建配置变化。

这些检查验证的是构建与基础仿真，不代表 PX4 HITL、无人机动力学标定或实飞已经通过。默认世界仅用于演示；用于真机的质量、惯量、推力和传感器参数需要来自实际设备的测量、标定或配置。

本机配置、上游源码克隆、日志与构建产物均被 Git 忽略。上游项目的版权与许可证声明保持不变。
