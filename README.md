# GazeboSimWin

Gazebo Harmonic 的 Windows 无界面、无渲染构建方案，支持 GNU（MSYS2 UCRT64）和 MSVC（vcpkg）两套工具链。

本仓库保存固定版本清单、源码补丁和构建脚本，以 `gz-sim 8.15.0` 标识这一组 Harmonic 组件。保留物理仿真、非渲染传感器和系统插件，裁去 Gazebo GUI、Qt、OGRE、渲染组件及依赖渲染的传感器，减少最终运行包体积。原生启动器为 `gz-sim-headless.exe`，默认使用 DART，也可选用 Bullet-featherstone。

## Gazebo 配置怎么改

Gazebo 运行配置主要在 **SDF 文件**中，不在构建用的 `toolchain.config.ps1` 中。本项目没有统一的飞机参数 `config.toml`。

| 要调整的内容 | 配置位置 |
|---|---|
| 仿真步长、实时因子 | 世界 SDF 的 `<world><physics>`：`max_step_size`、`real_time_factor`。 |
| 重力、地理原点、磁场、风 | `<world>` 下的 `gravity`、`spherical_coordinates`、`magnetic_field`、`wind`；风力还需要相应插件及模型配置。 |
| 质量、重心、惯量、碰撞形状、关节 | 模型 SDF 的 `<model><link>` 中的 `inertial`、`collision`，以及 `<model><joint>`。 |
| IMU、气压计、磁力计、GPS 等 | 模型的 `<sensor>`：类型、安装姿态、`update_rate`、`topic`、噪声；世界中加载对应系统插件。 |
| 电机、螺旋桨、气动 | 模型下的 `<plugin>`，如 `MulticopterMotorModel`、`LiftDrag`；参数须匹配实际机型。 |
| DART / Bullet-featherstone | Physics 系统插件的 `<engine><filename>`，或启动参数 `--physics-engine`（优先级更高）。 |
| 默认加载哪些系统插件 | `server.config`；仅在世界没有加载任何世界级系统时兜底，不会自动补齐 SDF 已有插件。 |
| 模型包描述 | `model.config` 指向模型 SDF，不负责设置物理参数。 |
| 模型、系统插件和物理引擎搜索目录 | `GZ_SIM_RESOURCE_PATH`、`GZ_SIM_SYSTEM_PLUGIN_PATH`、`GZ_SIM_PHYSICS_ENGINE_PATH`。 |

修改 SDF 后，重新启动并加载该文件即可生效，**不需要重新编译 Gazebo**。修改插件 C++ 实现或增加本运行包没有的功能，才涉及重新构建。

### 直接运行配置示例

[examples/headless.sdf](examples/headless.sdf) 是带中文注释的完整配置：地面、自由下落刚体、IMU 和位姿输出，不依赖 GUI、渲染或在线模型。构建完成后，在仓库根目录运行：

```powershell
# GNU 运行包；使用 MSVC 时将 gnu 改为 msvc。
$bin = Join-Path (Get-Location).Path 'dist/gnu/gz-sim-harmonic-8.15.0/bin'
$world = (Resolve-Path './examples/headless.sdf').Path
& "$bin/gz-sim-headless.exe" $world -r --stats -v 3

# 切换物理引擎，无需改模型或重新编译。
& "$bin/gz-sim-headless.exe" $world -r --physics-engine gz-physics-bullet-featherstone-plugin
```

第一条命令会持续运行；按 Ctrl+C 退出后再执行第二条。查看 IMU 数据时，在另一个 PowerShell 窗口、仓库根目录执行：

```powershell
./dist/gnu/gz-sim-harmonic-8.15.0/bin/gz-transport-topic.exe -e -t /demo/imu -n 1
```

示例中的质量、尺寸、步长和采样率是演示配置，惯量由示例几何推导；没有标定真实飞机，也没有加入传感器误差。换机型时应使用测量、标定或设备读回的参数。参数单位、来源、插件搭配、模型路径、`server.config` 加载规则及 PX4 对接边界，见 [Gazebo 运行配置说明](docs/gazebo-configuration.md)。

## 快速构建

在 Windows PowerShell 中克隆仓库，并创建本机工具链配置：

```powershell
git clone https://github.com/coasho/GazeboSimWin.git
cd GazeboSimWin
Copy-Item patch/harmonic-8.15.0/toolchain.config.example.ps1 patch/harmonic-8.15.0/toolchain.config.ps1
notepad patch/harmonic-8.15.0/toolchain.config.ps1
```

已有本机配置时直接编辑，不要再次用模板覆盖。核对实际工具链路径后，选择一套工具链构建：

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

拷贝整个运行包目录，双击其中的 `bin/gz-sim-headless.exe` 即可启动自带的 `headless_default.sdf` 箱体下落演示。上面的仓库示例 `examples/headless.sdf` 是单独的文件，需要显式传入路径；不会自动覆盖运行包默认世界。

构建环境、工具链配置字段、依赖清单、分阶段构建与补丁维护方法见 [中文构建说明](patch/harmonic-8.15.0/README.md)。这些是构建配置，与 Gazebo 的运行配置分开管理。

## 验证范围

此前本地验证覆盖两套工具链构建、运行包搬移、干净 `PATH` 启动，以及 DART / Bullet-featherstone 下的箱体自由落体和落地检查。Release 运行包历史测量值：GNU 约 93.8 MiB，MSVC 约 72.2 MiB；实际大小随依赖和构建配置变化。

本次文档示例 `examples/headless.sdf` 已在现有 GNU / MSVC 运行包上分别用 DART 和 Bullet-featherstone 检查：四组均正常退出，收到 IMU 和位姿消息，箱体落地质心高度约为 0.5 m（由 1 m 边长推导）。本次只修改文档与示例，未重新构建运行包。

这些检查验证的是构建与基础仿真，不代表 PX4 HITL、无人机动力学标定或实飞已经通过。默认世界仅用于演示；用于真机的质量、惯量、推力和传感器参数需要来自实际设备的测量、标定或配置。

本机配置、上游源码克隆、日志与构建产物均被 Git 忽略。上游项目的版权与许可证声明保持不变。
