# Headless Gazebo Harmonic 8.15.0 for Windows

Gazebo Harmonic (gz-sim8 8.15.0) patched for a headless, no-GUI, no-rendering build on
Windows, with either the GNU toolchain (MSYS2 UCRT64) or MSVC. `build.ps1` fetches and
patches the sources, builds and installs everything, then packs a portable folder that
runs on a clean Windows 10/11 x64 machine with nothing installed.

## Quick start

1. Copy `toolchain.config.example.ps1` to `toolchain.config.ps1`, then edit the
   MSYS2 root, Visual Studio / vcpkg and Python paths for your machine. The local
   configuration is ignored by Git so personal paths are not published.
2. Build (from this directory):

   ```bat
   build.cmd gnu
   build.cmd msvc
   ```

   or `powershell -ExecutionPolicy Bypass -File build.ps1 -Toolchain gnu`.
3. Result: `<repo>\dist\<toolchain>\gz-sim-harmonic-8.15.0\`. Copy that folder anywhere
   and double-click `bin\gz-sim-headless.exe`.

Stages can be run separately: `-Stages fetch,deps,build,dist`, `-Only <package>`,
`-Clean`, `-Config Release|RelWithDebInfo|Debug`, `-KeepVersionedPlugins`.

Measured on this machine (Release): GNU package 93.8 MB (1556 files), MSVC package
72.2 MB (1496 files). Both run from any location with a PATH that only contains
`C:\Windows\System32` (DART and Bullet-featherstone checked with a falling body).

Requirements: Windows 10/11 x64, git, and either MSYS2 (UCRT64) or Visual Studio 2022+
with the C++ workload (its bundled vcpkg and CMake are used) plus a Python 3. The first
MSVC build compiles ~65 vcpkg packages and takes a while; later builds hit vcpkg's binary
cache.

## Layout

| Path | Content |
|---|---|
| `repos.txt` | pinned repositories and tags (`gz` = Gazebo, `gnu` = third-party built from source for GNU) |
| `patches/<name>.patch` | all modifications of that repository relative to its tag |
| `toolchain.config.example.ps1` | portable configuration template; copy to Git-ignored `toolchain.config.ps1` and set actual toolchain paths |
| `msys2-packages.txt` | MSYS2 packages for the GNU build (installed by `build.ps1` when missing) |
| `vcpkg.json` | vcpkg manifest for the MSVC build (baseline pinned) |
| `build.ps1` / `build.cmd` | fetch, deps, build, dist |
| `make-patches.ps1` | regenerate `patches/` from the working trees in `src/` |

Directories created next to `patch/`: `src/` (sources), `build/<toolchain>/`,
`install/<toolchain>/` (developer install with headers and CMake configs),
`dist/<toolchain>/` (portable runtime package).

## What was removed

| Removed | How |
|---|---|
| gz-gui8, gz-rendering8, gz-launch7, Qt, OGRE | not built; `GZ_SIM_HEADLESS=ON` (gz-sim), `GZ_SENSORS_WITHOUT_RENDERING=ON` (gz-sensors) |
| GUI plugins, rendering component, rendering systems (`sensors`, `camera-video-recorder`, `dvl`, `lens-flare`, `model-photo-shoot`, `shader-param`) | `GZ_SIM_HEADLESS=ON` |
| camera, depth/rgbd/thermal/segmentation/bounding-box/wide-angle cameras, lidar, GPU lidar, DVL sensors | `GZ_SENSORS_WITHOUT_RENDERING=ON` |
| gz-common `av` (FFmpeg) | `SKIP_av=ON` |
| GDAL (DEM terrain files) | `GZ_COMMON_WITHOUT_GDAL=ON`: `common::Dem::Load` reports an error, image heightmaps still work |
| Remotery profiler | `GZ_PROFILER_REMOTERY=OFF` |
| gz-tools2 / Ruby `gz sim` command line, world thumbnails | replaced by the native `gz-sim-headless.exe` |

Kept: DART (default) and Bullet / Bullet-featherstone / TPE physics engines, all
non-rendering sensors (IMU, magnetometer, air pressure, air speed, altimeter, NavSat,
force-torque, contact, logical camera), all other systems (multicopter motor model &
control, lift-drag, advanced lift-drag, wind, hydrodynamics, thruster, buoyancy, battery,
joint controllers, …), gz-transport, gz-fuel-tools, SDFormat, logging/playback.

## gz-sim-headless.exe

Native replacement for `gz sim -s`. Same options as the Ruby command line for the server
(`-r`, `-v`, `--iterations`, `-z`, `--physics-engine`, `--record*`, `--playback`,
`--levels`, `--network-role`, `--seed`, …) plus `--stats`. The world argument is looked up
like before: file path, `GZ_SIM_RESOURCE_PATH` (`;` separated), installed worlds, Fuel.
ERB templates are not supported.

Started without arguments (double click) it runs `headless_default.sdf` (a box with an IMU
dropping onto the ground) and prints simulation time / real time factor.

```bat
gz-sim-headless.exe my_world.sdf -r -v 3
gz-sim-headless.exe my_world.sdf -r --physics-engine gz-physics-bullet-featherstone-plugin
```

Plugin and resource paths are computed from the location of the DLLs
(`GZ_ENABLE_RELOCATABLE_INSTALL=ON`), so the folder can be moved freely. Custom systems
are found through `GZ_SIM_SYSTEM_PLUGIN_PATH` as usual. `bin\gz-transport-topic.exe` and
`bin\gz-transport-service.exe` replace `gz topic` / `gz service`.

Plugin file names: only the unversioned names are packaged
(`gz-sim-imu-system`, `gz-physics-dartsim-plugin`, as used by SDF files). Use
`-KeepVersionedPlugins` if your worlds reference `gz-sim8-...` names.

## Windows fixes contained in the patches

Besides the headless options, the patches fix issues that show up on Windows:

| Repository | Fix |
|---|---|
| gz-cmake | `FindZeroMQ` uses pkg-config on MinGW; `FindGzBullet` drops `optimized`/`debug` keywords (vcpkg) |
| gz-common | plugin lookup also tries `lib<name>.dll` (MinGW); Rpcrt4 linked explicitly |
| gz-msgs | descriptor set opened in binary mode (dynamic messages were broken) |
| gz-transport | uuid/Rpcrt4/Winsock/IP Helper linked on MinGW |
| gz-physics | MSVC-only flags limited to MSVC; unversioned plugin copy works with a CMake path containing spaces |
| gz-sim | same plugin copy fix; `:` removed from the default log directory name; no bogus env warning; missing `events` / `plugin::loader` links; native launcher |
| sdformat, urdfdom, urdfdom_headers, fcl, DART | missing `<cstdint>` / `<cassert>`, C++14 for Eigen 5, MinGW cast fix (GNU only deps) |

The GNU build compiles libccd, fcl, console_bridge, urdfdom and DART (static) from source
because MSYS2 does not package them; the MSVC build takes them from vcpkg.

## Updating the patches

Edit the sources in `src/<name>`, rebuild, then run `make-patches.ps1`. Several upstream
files use CRLF line endings; edit them with an editor that keeps them, otherwise the whole
file ends up in the patch.
