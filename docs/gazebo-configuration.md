# Gazebo 运行配置说明

本文针对本仓库的无渲染 `gz-sim 8.15.0`。配置项已按仓库锁定的源码和补丁核对；不是 Gazebo Classic 的配置教程。`toolchain.config.ps1` 仅供构建脚本使用，与下文运行参数无关。

## 1. 配置文件分别管什么

| 文件 | 职责 |
|---|---|
| 世界 SDF（例如 `world.sdf`） | 包含 `<sdf><world>`，配置物理步长、环境、模型实例和世界级系统插件；作为启动器的输入。 |
| 模型 SDF（通常叫 `model.sdf`） | 包含 `<sdf><model>`，配置刚体、质量惯量、碰撞、关节、传感器和模型级插件；由世界 `<include>` 引用，或直接写进世界。 |
| 模型包的 `model.config` | XML 格式的模型描述，指定包名、版本和模型 SDF 文件；不是物理参数文件。 |
| `server.config` | XML 格式的默认系统插件列表；只在未加载世界级系统时兜底。 |
| 启动参数与环境变量 | 选择世界/引擎、运行方式和资源搜索路径。 |

通常修改 SDF 后重启仿真即可，不必编译。SDF 不是脚本：不会自动计算表达式或展开 `${变量}`；本启动器也不支持 ERB。派生数值要先算好再填入，修改相关输入后同步重算。

建议将自己项目的世界和模型另存到专用目录并纳入版本管理。不要只改 `dist/` 中的文件，因为重新打包会重建运行目录。

## 2. 从可运行示例开始

完整文件：[examples/headless.sdf](../examples/headless.sdf)。它显式加载 Physics、UserCommands、Imu 和模型级 PosePublisher；没有灯光、GUI、visual、摄像头，也不需要下载模型。

在仓库根目录运行；使用 MSVC 时把路径中的 `gnu` 改成 `msvc`：

```powershell
$bin = Join-Path (Get-Location).Path 'dist/gnu/gz-sim-harmonic-8.15.0/bin'
$world = (Resolve-Path './examples/headless.sdf').Path
& "$bin/gz-sim-headless.exe" $world -r --stats -v 3
```

`-r` 表示立即开始，`--stats` 输出仿真时间和实际实时因子，Ctrl+C 结束。显式指定世界时，不加 `-r` 会从暂停状态开始。只想做有限时长检查，可由目标仿真时长和 SDF 步长推导迭代数：

```powershell
[xml]$sdf = Get-Content -Raw $world
$step = [double]::Parse($sdf.sdf.world.physics.max_step_size, [Globalization.CultureInfo]::InvariantCulture)
$checkSeconds = 2.0 # 仅为本次演示检查时长，不是飞控参数。
$iterations = [int][Math]::Ceiling($checkSeconds / $step)
& "$bin/gz-sim-headless.exe" $world -r --iterations $iterations --stats -v 3
```

在另一个 PowerShell 窗口、仓库根目录查看话题（仿真应保持运行）：

```powershell
$bin = Join-Path (Get-Location).Path 'dist/gnu/gz-sim-harmonic-8.15.0/bin'
& "$bin/gz-transport-topic.exe" -l
& "$bin/gz-transport-topic.exe" -e -t /demo/imu -n 1
& "$bin/gz-transport-topic.exe" -e -t /model/box/pose -n 1
```

`-n 1` 收到一条消息后退出。IMU 系统有订阅者时才执行数据更新；`always_on` 不能替代订阅，也不能让暂停的仿真继续生成数据。

### 示例数值从哪里来

以下数值是已有 `headless_default.sdf` 的演示配置，不是无人机标定结果：

| 示例参数 | 来源、依赖与换平台时的调整 |
|---|---|
| 步长 `0.001 s`、目标实时因子 `1` | 演示的离散时间和运行速度配置；按实际控制周期、传感器频率、动力学时间常数和计算能力重新选择，并做步长收敛检查。 |
| 质量 `1 kg`、尺寸 `1 × 1 × 1 m` | 假定的均匀立方体；真实模型使用称重、几何测量或可靠 CAD 数据。 |
| 主惯量 `1/6 kg·m²`，乘积惯量为零 | 由均匀立方体的质量与尺寸推导；质心与 link 原点重合。改变尺寸/质量后重算，不能照抄到飞机。 |
| 初始高度 `5 m`、姿态为零 | 自由落体演示的初始条件；换场景按实际起始位置、姿态和碰撞间隙配置。 |
| 重力 `0 0 -9.8 m/s²` | 演示采用 Z 向上的近似重力；实际场景按当地重力及所用世界坐标系配置。 |
| 地面尺寸 `100 × 100 m`、法向 `0 0 1` | 演示平面配置；物理引擎对 plane 的物理边界处理可能不同，不要把 size 当作必然的有限场地边界。有限地面请建有厚度的碰撞体。 |
| IMU `100 Hz`、位姿发布 `10 Hz` | 分别为示例传感器采样与观察输出频率；不是飞控推荐频率。IMU 周期对应当前步长的 10 次迭代，位姿为 100 次。 |
| IMU 安装变换为零、未设噪声 | 理想化基础检查条件；真实平台应测量安装变换，加入传感器标定误差，并另行验证延迟/丢包。 |

## 3. 物理时间、引擎与环境

### 步长和实时因子

`<world><physics><max_step_size>` 单位为秒；当前仿真循环使用它推进仿真时间。`real_time_factor` 是期望的“仿真时间 / 墙钟时间”，不是精度参数，也不保证机器能达到。

修改 `real_time_factor` 不等于修改积分步长。传感器 `update_rate` 单位为 Hz，按仿真时间调度；例如实际实时因子不足时，墙钟时间观察到的发布率也会下降。对控制与传感器周期，尽量使周期对应整数个仿真步，且用减小步长的对照试验检查结果是否收敛，不要只以“运行没报错”为准。

本版本主要使用 `max_step_size` 和 `real_time_factor` 设置循环周期，不要照搬 Classic 的 `real_time_update_rate` 并假定它具有同样效果。启动器的 `-z` 可覆盖循环更新率，它不是传感器采样率；一般先用 SDF 管理时间配置，避免多处覆盖。

### 选择物理引擎

示例在世界中显式配置：

```xml
<plugin filename="gz-sim-physics-system" name="gz::sim::systems::Physics">
  <engine>
    <filename>gz-physics-dartsim-plugin</filename>
  </engine>
</plugin>
```

改为 `gz-physics-bullet-featherstone-plugin` 即可在 SDF 中选择另一引擎。命令行可临时覆盖：

```powershell
& "$bin/gz-sim-headless.exe" $world -r --physics-engine gz-physics-bullet-featherstone-plugin
```

选择优先级为：启动参数 `--physics-engine` > Physics 插件内 `engine/filename` > 默认 DART。`<physics type="ignored">` 不负责选择引擎，改成 `ode` 也不是给这个运行包增加 ODE 支持。

不同引擎对关节、接触、摩擦、碰撞形状及特定 API 的支持不同；写进 SDF 不代表该引擎一定执行。切换后需重新检查有关功能和结果，不应只比较运行速度。

### 世界环境

| `<world>` 中的字段 | 含义与配置依据 |
|---|---|
| `gravity` | 世界坐标下的重力向量，单位 m/s²。 |
| `spherical_coordinates` | 地理参考：`surface_model`、`world_frame_orientation`、`latitude_deg`、`longitude_deg`、`elevation`、`heading_deg`。按实际场地/坐标约定配置；NavSat 使用它将局部位置转换为地理位置。 |
| `magnetic_field` | 世界坐标下磁场向量，单位 T；磁力计仿真应使用对应地点和坐标系的值。 |
| `wind/linear_velocity` | 风速向量，单位 m/s。仅填写此值不等于所有物体都获得了气动力；需要按所用风/气动插件配置作用对象与参数。 |

`WindEffects` 使用世界级插件 `gz-sim-wind-effects-system`，有关 link 通过 `enable_wind` 参与其作用。电机和气动系统也可能使用风信息；同时启用多种外力模型前，检查是否重复计算了阻力。

## 4. 模型质量、惯量、碰撞和坐标系

`<model><link><inertial>` 中：

- `mass` 为 kg。
- `pose` 定义惯性坐标系相对 link 的位置与姿态；位置对应重心。
- `inertia` 的六个分量单位为 kg·m²，在该惯性坐标系下填写，应形成物理可实现的惯量矩阵。

均匀长方体的主惯量为 `Ixx = m × (y² + z²) / 12`，另外两轴循环替换。此公式依赖“均匀长方体”假设，不能用飞机外接包围盒直接代替实机惯量；应使用质量分布、CAD 或试验辨识。

`collision` 定义碰撞形状，`visual` 只定义显示外观。裁去显示时保留 `collision`、`inertial`、`joint` 和传感器；还应保留碰撞使用的网格资源。质心、接触面、关节轴或惯量错误都可能表现为落地弹跳、翻转或电机力矩方向不对。

默认形式的 `pose` 为 `x y z roll pitch yaw`，单位 m / rad；引用 `relative_to` 或嵌套模型时还需核对参考坐标系。示例的世界 Z 向上，不是 PX4 的 NED/FRD 约定；对接层必须正确转换位置、速度、姿态、角速度和加速度，不能仅交换某两个字段。

## 5. 非渲染传感器与噪声

添加传感器需要同时做两件事：模型中定义 `<sensor>`，世界中加载对应的系统插件。`gz-sim-sensors-system` 是本裁剪版删除的渲染传感器系统，不能用它代替下表插件。

| sensor 类型 | 系统插件 filename | 插件 name |
|---|---|---|
| `imu` | `gz-sim-imu-system` | `gz::sim::systems::Imu` |
| `magnetometer` | `gz-sim-magnetometer-system` | `gz::sim::systems::Magnetometer` |
| `air_pressure` | `gz-sim-air-pressure-system` | `gz::sim::systems::AirPressure` |
| `air_speed` | `gz-sim-air-speed-system` | `gz::sim::systems::AirSpeed` |
| `altimeter` | `gz-sim-altimeter-system` | `gz::sim::systems::Altimeter` |
| `navsat` | `gz-sim-navsat-system` | `gz::sim::systems::NavSat` |
| `contact` | `gz-sim-contact-system` | `gz::sim::systems::Contact` |
| `force_torque` | `gz-sim-forcetorque-system` | `gz::sim::systems::ForceTorque` |

例如气压计系统写在 `<world>` 下：

```xml
<plugin filename="gz-sim-air-pressure-system" name="gz::sim::systems::AirPressure"/>
```

大多数上述传感器定义在 `<link>` 下；力矩传感器定义在 `<joint>` 下；接触传感器还需要引用碰撞体。插件存在不代表所有传感器行为都已在两种引擎上验证。

传感器的 `pose` 是安装变换，`update_rate` 是仿真采样频率，`topic` 是 Gazebo Transport 话题，不是串口或 MAVLink 地址。多机时为各实例设置独立话题和插件命名空间，避免同名数据混合。

IMU 的噪声分别位于 `<imu><angular_velocity><x|y|z><noise>` 和 `<imu><linear_acceleration><x|y|z><noise>`。这里的 `x|y|z` 表示三个独立元素，不是可直接复制的 XML 标签。按轴配置 `type="gaussian"` 或 `gaussian_quantized` 时：

| noise 字段 | 含义与来源 |
|---|---|
| `mean`、`stddev` | 每次测量的噪声均值和标准差；使用对应采样率、滤波条件下的标定数据，不能把数据手册中的噪声密度直接当标准差。 |
| `bias_mean`、`bias_stddev` | 静态偏置分布参数；由多次上电/静态采样辨识。 |
| `dynamic_bias_stddev`、`dynamic_bias_correlation_time` | 随时间变化的偏置模型参数；后者单位为秒，需按长时间记录辨识。 |
| `precision` | 量化步长，用于 `gaussian_quantized`；按实际输出量化分辨率配置。 |

陀螺仪测量量单位为 rad/s，加速度计为 m/s²。示例没有噪声，是理想传感器；噪声配置也不自动提供安装松动、通信延迟、丢包或时钟误差，这些需要在对应模型/接口层补充和验证。

## 6. 无人机电机与气动参数

多旋翼电机系统使用模型级插件 `gz-sim-multicopter-motor-model-system`，类名 `gz::sim::systems::MulticopterMotorModel`。每个旋翼分别配置插件，并匹配实际关节、link 和电机编号。当前实现使用 `motorType=velocity`；position / force 模式未实现。

| 插件字段 | 含义与换机型依据 |
|---|---|
| `jointName`、`linkName` | 对应旋翼关节和刚体，必须与模型名称和轴向一致。 |
| `actuator_number`、`turningDirection` | 执行器数组下标（从零开始）及 `cw` / `ccw` 旋向；依据真实电机布局和飞控混控映射。 |
| `robotNamespace`、`commandSubTopic` | 组合成命令订阅话题；与桥接端输出保持一致。 |
| `maxRotVelocity` | 转速上限，rad/s；从实际电机/桨/电压组合的测试或可靠数据得到。 |
| `motorConstant` | 常规正推力运行时，推力大小 `T = motorConstant × ω²`；按推力台的转速—推力数据拟合。 |
| `momentConstant` | 反扭矩大小与推力之比（量纲 m），旋向决定符号；应由扭矩和推力数据辨识，而非把它当另一份平方转速系数。 |
| `timeConstantUp`、`timeConstantDown` | 电机加速、减速的一阶响应时间常数，单位 s；按实际电机/电调/桨组合的动态响应辨识。 |
| `rotorDragCoefficient`、`rollingMomentCoefficient` | 旋翼气动阻力和滚转力矩模型系数；按插件方程与机型试验数据校准，不能沿用其他机型常数。 |
| `rotorVelocitySlowdownSim` | 仿真旋翼关节转速的缩放系数；不是实机传动比，插件会在计算力时还原转速。与步长、最高转速共同检查混叠和动力学结果。 |

命令消息是 `gz.msgs.Actuators`，当前 velocity 模式从 `velocity[actuator_number]` 读取目标角速度。它不是 PWM，也不是可以直接照搬的归一化油门；飞控输出转换须匹配实际推力曲线和接口约定。

固定翼可用 `LiftDrag` / `AdvancedLiftDrag`，但面积、气动中心、轴向和气动系数都应来自对应机型。本仓库保留了这些插件，不代表已经完成任何真实机型标定。

**SDF 不负责把 SITL 切换为 HITL。** 本仓库提供 Gazebo 物理侧，不提供完整 PX4/MAVLink 硬在环桥接配置。飞控 HIL 参数、固件能力、执行器映射、连接方式、时钟同步和失联行为仍需在 PX4 与接口层配置、联调。仿真运行不等于可以安全实飞。

## 7. 本地模型包与搜索路径

一个可被世界包含的模型目录通常组织为：

```text
simulation/
  worlds/
    flight.sdf
  models/
    aircraft/
      model.config
      model.sdf
      meshes/
  plugins/
```

`model.config` 的最小描述可以写成：

```xml
<?xml version="1.0"?>
<model>
  <name>aircraft</name>
  <version>1.0</version>
  <sdf version="1.9">model.sdf</sdf>
  <description>本地机型模型</description>
</model>
```

其中 `version=1.0` 是示例模型包版本，`sdf version=1.9` 是所引用文件的格式版本，不是 Gazebo 产品版本。世界中用 `<include><uri>model://aircraft</uri></include>` 引用；`GZ_SIM_RESOURCE_PATH` 应包含 `models` 这个父目录，而不是只指向 `aircraft`。

假设已按上面的目录布局创建 `simulation`，在它的父目录中配置：

```powershell
$simRoot = (Resolve-Path './simulation').Path
$resources = @((Join-Path $simRoot 'worlds'), (Join-Path $simRoot 'models'))
if ($env:GZ_SIM_RESOURCE_PATH) { $resources += $env:GZ_SIM_RESOURCE_PATH }
$env:GZ_SIM_RESOURCE_PATH = $resources -join ';'

# 只有存在自定义系统插件时才需要此项；保留已有搜索目录。
$plugins = @((Join-Path $simRoot 'plugins'))
if ($env:GZ_SIM_SYSTEM_PLUGIN_PATH) { $plugins += $env:GZ_SIM_SYSTEM_PLUGIN_PATH }
$env:GZ_SIM_SYSTEM_PLUGIN_PATH = $plugins -join ';'
```

Windows 下路径列表用分号；`$env:` 设置只影响当前会话及其后启动的子进程。内置资源和插件由运行包自动定位，不必再次添加。

`GZ_SIM_SYSTEM_PLUGIN_PATH` 查找系统插件，`GZ_SIM_PHYSICS_ENGINE_PATH` 查找自定义物理引擎插件；两者不是同一目录变量。自定义 C++ 插件应与运行包使用相同工具链及兼容依赖，不能混用 GNU/MSVC DLL。插件自身被找到也不保证其依赖 DLL 能被找到。

## 8. server.config 的加载规则

当前版本的启动过程先加载 SDF 中的系统。如果世界实体没有加载任何系统，才读取默认插件配置。**已有一个世界级插件就不会再自动从 server.config 补齐 Physics 或 Imu**，所以本示例直接在 SDF 中列全所需系统。

默认配置位置为用户主目录下的 `.gz/sim/8/server.config`；首次缺失时从安装目录复制。已有用户副本不会因为更新运行包就自动更新。可显式指定另一个默认配置：

```powershell
$env:GZ_SIM_SERVER_CONFIG_PATH = (Resolve-Path './simulation/server.config').Path
```

这是一个文件路径，不是目录列表。该变量仅改变兜底配置的位置，不会强制覆盖显式 SDF 插件；指向不存在的文件时不会继续回退到用户默认文件。也不要把 SDF 世界路径填入此变量。

用于无世界级插件 SDF 的最小物理 + IMU 默认配置示例：

```xml
<server_config>
  <plugins>
    <plugin entity_name="*" entity_type="world"
            filename="gz-sim-physics-system" name="gz::sim::systems::Physics"/>
    <plugin entity_name="*" entity_type="world"
            filename="gz-sim-imu-system" name="gz::sim::systems::Imu"/>
  </plugins>
</server_config>
```

`entity_name` / `entity_type` 指定挂载目标；`filename` 是插件库名，`name` 是注册类名。默认打包仅保留不带主版本号的插件名，例如 `gz-sim-imu-system`。已有配置使用 `gz-sim8-...` 名称时，应改为上述名称或打包时加 `-KeepVersionedPlugins`。

## 9. 配置不生效时先查什么

| 现象 | 优先检查 |
|---|---|
| 世界运行但刚体不动 | 是否带 `-r`、是否设为 `static`、Physics 是否加载、是否误以为默认配置会补齐插件。 |
| 找不到模型 | `model://` 名称与目录是否一致，资源变量是否指向模型包父目录，`model.config` 是否引用正确 SDF。 |
| 找不到插件或 DLL | 是否引用了被裁去的系统，名称是否带版本号，搜索路径、工具链和依赖 DLL 是否匹配。 |
| 找得到 IMU 话题但没有数据 | 是否运行而非暂停、是否有订阅者、话题是否匹配、进程是否使用相同 `GZ_PARTITION`。 |
| 采样率不符合预期 | 区分仿真时间与墙钟时间，检查步长和传感器周期、实时因子以及负载。 |
| 电机不转或推力方向错误 | 关节/link 名、执行器下标、话题命名空间、转速单位、关节轴和旋向。 |

排查时先使用 `-v 4` 查看插件加载信息。表中的 4 是启动器定义的日志等级，不是物理参数。修改配置后重新加载该文件；仅修改磁盘文件不会自动更新正在运行的仿真。
