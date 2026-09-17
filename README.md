# GazeboSimWin

Reproducible patches and Windows build scripts for headless Gazebo Harmonic
(gz-sim 8.15.0), using GNU / MSYS2 UCRT64 or MSVC / vcpkg.

The build keeps simulation, physics, non-rendering sensors and system plugins,
and excludes Gazebo GUI, rendering, Qt, OGRE and rendering-based sensors.
DART and Bullet-featherstone are supported. The native launcher is
`gz-sim-headless.exe`.

## Build

Clone this repository, then create the local toolchain configuration in PowerShell:

```powershell
git clone https://github.com/coasho/GazeboSimWin.git
cd GazeboSimWin
Copy-Item patch/harmonic-8.15.0/toolchain.config.example.ps1 patch/harmonic-8.15.0/toolchain.config.ps1
```

Edit `toolchain.config.ps1` to match the installed toolchains before building:

```powershell
./patch/harmonic-8.15.0/build.cmd gnu
# Or:
./patch/harmonic-8.15.0/build.cmd msvc
```

Scripts fetch the pinned upstream tags, apply the patches, build dependencies and
Gazebo, and package the result under `dist/<toolchain>/gz-sim-harmonic-8.15.0/`.
Local configuration, upstream checkouts, logs and build artifacts are Git-ignored.

See [the build documentation](patch/harmonic-8.15.0/README.md) for requirements,
removed features, runtime options, patch maintenance and known limitations.

## Validation scope

Previous local verification covered both compiler builds and relocated runtime
packages with a clean PATH, including falling-body checks with DART and
Bullet-featherstone. These checks validate the build and basic simulation;
they do not validate PX4 HITL, aircraft calibration or real-flight performance.
The bundled default world is a demonstration, not an aircraft parameter set.

Upstream projects and their copyright and license notices remain under their
respective terms; this repository stores patches, not a vendored source tree.
