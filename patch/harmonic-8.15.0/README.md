# Gazebo Harmonic 8.15.0 Windows 无界面构建

本目录提供 Gazebo Harmonic 的无 GUI、无渲染补丁，以及 GNU（MSYS2 UCRT64）和 MSVC（vcpkg）构建脚本。目录版本号对应 `gz-sim 8.15.0`；其他 Harmonic 组件的版本独立固定在 `repos.txt` 中。

`build.ps1` 负责克隆源码、应用补丁、构建依赖、编译安装及收集运行时 DLL，最终生成便携运行目录。

## 环境与快速开始

目标平台为 Windows x64。此前在本机完成了 GNU、MSVC 构建及搬移后的运行检查；尚未覆盖所有 Windows 10/11 版本和工具链组合。

| 工具链 | 构建环境 |
|---|---|
| 公共 | Git，可访问清单中的上游仓库和包源。 |
| GNU | MSYS2 UCRT64，包含 GCC、CMake、Ninja、Python 等。第三方包见 `msys2-packages.txt`。 |
| MSVC | 带 C++ 工作负载、Windows SDK、CMake/Ninja 和 vcpkg 的 Visual Studio，以及独立安装的 Python 3。此前实测使用 VS 18；脚本使用 `vcvars64.bat`。 |

在仓库根目录运行：

```powershell
# 首次使用时创建本机配置；已有配置请直接编辑，避免覆盖。
Copy-Item patch/harmonic-8.15.0/toolchain.config.example.ps1 patch/harmonic-8.15.0/toolchain.config.ps1
notepad patch/harmonic-8.15.0/toolchain.config.ps1

# 按安装环境修改配置后，选择一种构建方式。
./patch/harmonic-8.15.0/build.cmd gnu
./patch/harmonic-8.15.0/build.cmd msvc
```

MSVC 首次需要下载并构建较多 vcpkg 依赖，之后可复用二进制缓存。GNU 在允许自动安装时，会用 pacman 补齐清单中缺少的包。

结果位于 `<仓库>/dist/<gnu或msvc>/gz-sim-harmonic-8.15.0/`。复制整个目录后运行 `bin/gz-sim-headless.exe`，不要只复制 EXE。

## 构建配置文件

### 模板与本机配置

`toolchain.config.example.ps1` 是配置模板；复制为同目录下的 `toolchain.config.ps1` 后才会被构建脚本读取。只修改模板不会改变已有本机配置。

配置格式是 PowerShell 哈希表 `$Cfg = @{ ... }`，不是 JSON 或 TOML。路径建议使用单引号；PowerShell 中反斜杠无需写成双反斜杠。配置文件会被脚本直接执行，因此应仅放入自己确认过的配置内容。

`toolchain.config.ps1` 已被 Git 忽略，可保存本机路径。不要强制提交此文件；需要共享新的配置项时，更新模板和文档。

### 通用字段

| 字段 | 模板值 | 含义与调整方法 |
|---|---|---|
| `Git` | `'git'` | 克隆源码所用的 Git 命令，从启动脚本时的 `PATH` 查找；也可填实际 `git.exe` 的绝对路径。 |
| `SourceDir` | `'src'` | 上游源码目录。相对路径以仓库根目录为基准。 |
| `BuildDir` | `'build'` | CMake 构建目录根路径，脚本追加 `gnu` 或 `msvc` 子目录；MSVC 的 vcpkg 安装目录也位于此处。 |
| `InstallDir` | `'install'` | 开发用安装目录根路径，包含头文件、库和 CMake 配置；脚本追加工具链子目录。 |
| `DistDir` | `'dist'` | 便携运行包根路径，脚本追加 `<工具链>/gz-sim-harmonic-8.15.0`。打包阶段会重建这个运行包目录。 |
| `Jobs` | `0` | `0` 表示从本机逻辑处理器数量推导并行任务数；正整数表示指定并行数。应按内存容量和其他负载调整。 |

四个目录字段均可填写绝对路径。模板默认的 `src/`、`build/`、`install/`、`dist/` 已被 Git 忽略；若改为仓库内其他目录，需要同步补充忽略规则。构建目录和运行包目录必须专用，不能指向源码、个人文件或其他项目。

### GNU / MSYS2 字段

| 字段 | 模板值 | 含义与调整方法 |
|---|---|---|
| `Msys2Root` | `'C:/msys64'` | MSYS2 安装根目录，仅为示例。填写本机实际路径；此字段不支持留空自动查找。 |
| `Msys2Env` | `'ucrt64'` | MSYS2 环境子目录；已验证的 GNU 配置为 UCRT64。编译器、依赖库和 Python 应来自同一环境。 |
| `Msys2AutoInstall` | `$true` | 缺包时执行 `pacman -S --needed --noconfirm`。设为 `$false` 时只报出缺包清单，由使用者自行安装。 |

表中路径用正斜杠表示，模板中的反斜杠路径含义相同。`Msys2Root` 与 `Msys2Env` 拼接后应能找到 `<Msys2Root>/<Msys2Env>/bin/g++.exe`、`cmake.exe`、`ninja.exe` 和 `python.exe`。脚本先检查编译器并设置环境，再进入依赖安装阶段；自动补包不能替代 MSYS2 和基础编译器的首次安装。

GNU 构建使用 MSYS2 环境内的 Python，不读取下面的 `Python` 字段。依赖清单中的包名由脚本加上 UCRT64 对应前缀；清单没有锁定 pacman 包的具体版本。

### MSVC 字段

| 字段 | 模板值 | 含义与调整方法 |
|---|---|---|
| `VsInstall` | `''` | 留空时通过 `vswhere` 查找带 x64 C++ 工具的最新 VS；也可指定实际安装根目录，其中应有 `VC/Auxiliary/Build/vcvars64.bat`。 |
| `VcpkgRoot` | `''` | 留空时使用所选 VS 下的 `VC/vcpkg`；指定其他安装时，应包含 `vcpkg.exe` 和 `scripts/buildsystems/vcpkg.cmake`。 |
| `VcpkgTriplet` | `'x64-windows'` | vcpkg 目标及宿主 triplet。当前脚本按 Windows x64 构建和收集运行库；不能仅修改此字段就认为支持 ARM64 或 x86。 |
| `Python` | `'C:/Python3/python.exe'` | gz-msgs 代码生成使用的 Python 3 可执行文件。必须改为实际绝对路径，不支持留空自动查找；构建时脚本会重设 `PATH`。 |

仅 `VsInstall` 和 `VcpkgRoot` 支持留空自动查找。`Git` 可通过命令名在 `PATH` 中解析，其余工具链路径不能把空字符串当作自动查找。

### 换机器与更换工具链

换机器后从模板重新创建本机配置，核对实际工具链、Python 和输出目录。GNU 与 MSVC 的 C++ 插件及依赖库需要分别构建，不应交叉混用。

更换编译器、MSYS2 环境、vcpkg triplet 或主要依赖后，建议为 `BuildDir`、`InstallDir` 和 `DistDir` 选择新的专用目录。仅使用 `-Clean` 会删除所选包的构建目录，不会清理旧安装目录；旧安装中的残留 DLL 仍可能进入运行包。

如果要并存 Release 与 Debug，也应配置不同的目录。当前默认目录只按工具链区分，没有额外的构建类型子目录；历史便携包检查针对 Release。

## 版本清单与目录结构

| 文件或目录 | 内容 |
|---|---|
| `repos.txt` | 仓库名称、URL、tag 和分组。`gz` 为两套工具链都构建的 Gazebo 库，`gnu` 为 GNU 从源码构建的第三方依赖。 |
| `patches/<名称>.patch` | 对应仓库相对固定 tag 的修改。 |
| `msys2-packages.txt` | GNU 的 MSYS2 依赖包清单。 |
| `vcpkg.json` | MSVC 依赖、功能选项及固定的 `builtin-baseline`。 |
| `build.ps1` / `build.cmd` | 主构建脚本与命令行包装脚本。 |
| `make-patches.ps1` | 从本机源码工作区重新导出补丁。 |
| `<仓库>/src/` | 克隆并应用补丁后的上游源码。 |
| `<仓库>/build/<工具链>/` | 构建中间文件及缓存。 |
| `<仓库>/install/<工具链>/` | 开发用安装结果，包含头文件和库。 |
| `<仓库>/dist/<工具链>/` | 精简后的便携运行包。 |

这些目录是模板默认值。修改 `repos.txt` 的 tag 时必须重新核对补丁；修改 MSVC 依赖版本时需同时核对 `vcpkg.json`。GNU 的第三方来源为 MSYS2 包与清单中的源码，MSVC 的第三方来源为 vcpkg。

## 分阶段构建

| 阶段 | 行为 |
|---|---|
| `fetch` | 克隆固定 tag 并应用补丁。已存在的源码目录会跳过，不会自动更新 tag 或重新应用补丁。 |
| `deps` | GNU 检查并安装 MSYS2 包、编译源码依赖；MSVC 安装 vcpkg manifest。 |
| `build` | 按依赖顺序配置、编译并安装 Gazebo 库。 |
| `dist` | 从安装结果收集运行文件及 DLL，去除开发文件和重复插件；GNU 产物额外去除符号表。 |

默认执行全部阶段。以下示例在仓库根目录的 PowerShell 会话中直接调用 `.ps1`，以正确传递数组参数；不要将 `-Stages build,dist` 原样通过 `build.cmd` / `powershell.exe -File` 传递。

```powershell
# 如当前会话的执行策略阻止脚本，可只对当前进程放开。
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# 依赖已安装时，仅重新构建 gz-sim 并打包。
./patch/harmonic-8.15.0/build.ps1 -Toolchain gnu -Stages build,dist -Only gz-sim

# 从已有 MSVC 安装结果重新打包，保留带版本号的插件名。
./patch/harmonic-8.15.0/build.ps1 -Toolchain msvc -Stages dist -KeepVersionedPlugins
```

| 参数 | 说明 |
|---|---|
| `-Only` | 限定 Gazebo 构建及 GNU 源码依赖构建的包名；不会缩减 MSVC 的 vcpkg manifest，也不会自动构建所选包缺少的前置依赖。 |
| `-Clean` | 构建前删除所选包的构建目录，再重新配置。 |
| `-Config` | CMake 构建类型，默认 `Release`，也接受 `RelWithDebInfo`、`Debug`。便携包不保留 PDB，GNU 打包仍执行去符号处理。 |
| `-KeepVersionedPlugins` | 打包时保留 `gz-sim8-...`、`gz-physics7-...` 等带版本号的插件文件名；默认仅保留 SDF 常用的不带版本号名称。 |

当前脚本即使只执行 `fetch` 也会初始化所选工具链，因此仍需要有效的本机配置。构建失败会自动重试，最多三次；编译器反复崩溃时应保留首个错误并检查工具链和机器环境，不能把重试成功当作环境稳定性的证明。

## 运行时配置

`toolchain.config.ps1` 不会被运行程序读取。更改模型或物理参数，应修改运行时 SDF；本项目没有统一的飞机参数 `config.toml`。

| 配置来源 | 用途 |
|---|---|
| 世界 / 模型 `.sdf` 文件 | 世界物理配置、模型质量和惯量、关节、传感器及系统插件参数。 |
| 启动参数 | 指定世界文件、启动运行、物理引擎、迭代次数、记录与回放等，完整列表见 `--help`。 |
| `GZ_SIM_RESOURCE_PATH` | 自定义世界和模型资源搜索目录，Windows 下多个目录以分号分隔。 |
| `GZ_SIM_SYSTEM_PLUGIN_PATH` | 自定义系统插件搜索目录；插件应与运行包使用相同工具链及兼容依赖构建。 |
| `GZ_SIM_SERVER_CONFIG_PATH` | 指定默认系统插件配置文件，供 Gazebo 的默认插件加载逻辑使用。 |

程序支持按文件路径、资源搜索目录、已安装世界和 Fuel 查找世界；不支持 ERB 模板。自定义 world 文件需自行准备。进入运行包的 `bin` 目录后，例如：

```powershell
./gz-sim-headless.exe my_world.sdf -r --stats
./gz-sim-headless.exe my_world.sdf -r --physics-engine gz-physics-bullet-featherstone-plugin
./gz-sim-headless.exe --help
```

`-r` 表示启动后立即运行。未指定世界且未指定回放路径时，程序会运行自带的 `headless_default.sdf`，展示带 IMU 的箱体下落，并打印仿真时间和实时因子。

默认系统配置未通过环境变量指定时，Gazebo 会使用用户目录下 `.gz/sim/8/server.config`；该文件不存在时从安装目录复制。需要避免不同项目共用默认配置时，可显式指定 `GZ_SIM_SERVER_CONFIG_PATH`。SDF 中显式声明的插件仍按世界配置加载。

插件与安装资源路径通过 DLL 所在目录计算（`GZ_ENABLE_RELOCATABLE_INSTALL=ON`）。`gz-transport-topic.exe`、`gz-transport-service.exe` 分别提供话题与服务命令行功能。

SDF 通常使用 `gz-sim-imu-system`、`gz-physics-dartsim-plugin` 等名称。如果已有世界使用 `gz-sim8-...` 等带版本号名称，打包时加 `-KeepVersionedPlugins`。

## 裁剪与保留内容

| 裁剪内容 | 实现方式或影响 |
|---|---|
| gz-gui、gz-rendering、gz-launch、Qt、OGRE | 不构建；gz-sim 启用 `GZ_SIM_HEADLESS=ON`，gz-sensors 启用 `GZ_SENSORS_WITHOUT_RENDERING=ON`。 |
| GUI 插件及渲染系统 | 跳过 `sensors`、`camera-video-recorder`、`dvl`、`lens-flare`、`model-photo-shoot`、`shader-param` 等系统。 |
| 相机、深度 / RGBD / 热成像 / 分割等相机、激光雷达、GPU 雷达、DVL | 依赖渲染的传感器组件不构建。 |
| gz-common 的 `av` / FFmpeg | `SKIP_av=ON`，不提供依赖它的视频功能。 |
| GDAL / DEM 地形读取 | `GZ_COMMON_WITHOUT_GDAL=ON`，DEM 加载明确报错；图片高度图保留。 |
| Remotery 性能分析后端 | `GZ_PROFILER_REMOTERY=OFF`。 |
| gz-tools / Ruby 启动器、世界缩略图 | 不打包 Ruby 命令行和缩略图；使用原生 `gz-sim-headless.exe`。 |

保留 DART、Bullet、Bullet-featherstone、TPE 物理引擎，以及 IMU、磁力计、气压、空速、高度计、NavSat、力矩、接触和逻辑相机等非渲染传感能力。多旋翼电机与速度控制、LiftDrag、AdvancedLiftDrag、风场、浮力、电池、关节控制等系统，以及 gz-transport、gz-fuel-tools、SDFormat 和日志功能也保留。逻辑相机不生成图像。

## 补丁中的 Windows 兼容性修改

| 仓库 | 修改 |
|---|---|
| gz-cmake | MinGW 的 ZeroMQ 查找允许 pkg-config；处理 Bullet 的 `optimized` / `debug` 链接列表。 |
| gz-common | 插件搜索兼容 MinGW 的 `lib<名称>.dll`；显式链接 Rpcrt4。 |
| gz-msgs | 以二进制模式读取消息描述文件，避免 Windows 文本模式导致解析失败。 |
| gz-transport | 补齐 MinGW 的 UUID、Rpcrt4、Winsock 和 IP Helper 链接。 |
| gz-physics | MSVC 专用参数仅用于 MSVC；插件复制命令正确处理带空格的 CMake 路径。 |
| gz-sim | 同样修正插件复制路径；日志目录名兼容 Windows；补齐 `events`、`plugin::loader` 链接，提供原生启动器等。 |
| sdformat、urdfdom、urdfdom_headers、fcl、DART | 补充缺失的标准头文件、适配 Eigen 5 所需的 C++ 标准及 MinGW 类型转换等。 |

GNU 路径从源码构建 libccd、fcl、console_bridge、urdfdom 和静态 DART 等依赖；MSVC 路径使用 vcpkg 提供的版本。

## 验证记录与适用边界

此前在独立目录中重新克隆并应用补丁完成了两套构建，再将运行包搬移并用干净 `PATH` 检查基础物理行为。

| Release 运行包 | 历史测量大小 | 文件数 |
|---|---|---|
| GNU / UCRT64 | 约 93.8 MiB | 1556 |
| MSVC | 约 72.2 MiB | 1496 |

这是此前构建的测量结果，不是体积保证；依赖版本、编译器和配置变化后应重新测量。运行检查覆盖 DART 与 Bullet-featherstone 的箱体下落和接触地面，不能据此推断所有插件、机型或 Windows 环境都已验证。

这些结果不等于 PX4 HITL 或实飞验收。机型的质量、惯量、推力、气动和传感器误差参数需要来自实际平台的测量、标定或可追溯配置；默认演示世界不能直接作为真机参数来源。

## 更新补丁

修改 `src/<仓库名>` 中的源码并完成对应构建验证后，在仓库根目录的 PowerShell 会话中执行：

```powershell
./patch/harmonic-8.15.0/make-patches.ps1
# 或只导出指定仓库：
./patch/harmonic-8.15.0/make-patches.ps1 -Only gz-sim
```

脚本按各源码仓库的当前 `HEAD` 导出工作区改动，包括新增文件。为保持补丁基线正确，`HEAD` 应保持在 `repos.txt` 对应的 tag；不要先在源码仓库内提交修改后再期望此脚本包含已提交部分。

部分上游文件使用 CRLF，编辑时应保留其行尾。本仓库通过 `.gitattributes` 对 `.patch` 禁用文本转换，避免补丁中的原始 CRLF 被改写。提交前核对补丁能够应用到对应的干净 tag，并确认未包含本机路径或私人配置。上游版权和许可证声明保持不变。
