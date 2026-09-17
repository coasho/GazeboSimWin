# Copy this file to toolchain.config.ps1, which is ignored by Git.
# Set paths to the actual tool installations on the machine running the build.
# Only VsInstall and VcpkgRoot support empty strings for automatic discovery.

$Cfg = @{
  Git          = 'git'
  # Relative directories are resolved from the repository root.
  SourceDir    = 'src'
  BuildDir     = 'build'
  InstallDir   = 'install'
  DistDir      = 'dist'
  # 0 derives parallelism from the number of logical processors.
  # Set this to a lower local concurrency limit if memory is constrained.
  Jobs         = 0

  # GNU: replace this example path with the installed MSYS2 root.
  Msys2Root    = 'C:\msys64'
  Msys2Env     = 'ucrt64'
  Msys2AutoInstall = $true

  # MSVC: empty selects Visual Studio with C++ tools through vswhere.
  VsInstall    = ''
  # Empty uses the vcpkg bundled with the detected Visual Studio.
  VcpkgRoot    = ''
  # This build targets Windows x64; dependencies must use the matching triplet.
  VcpkgTriplet = 'x64-windows'
  # MSVC code generation: replace with the actual Python 3 executable path.
  # GNU uses Python from the configured MSYS2 environment instead.
  Python       = 'C:\Python3\python.exe'
}
