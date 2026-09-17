<#
.SYNOPSIS
  Build a headless (no GUI / no rendering) Gazebo Harmonic 8.15.0 for Windows
  with the GNU (MSYS2 UCRT64) or the MSVC toolchain, and package it as a
  portable directory that runs without installing anything.

.DESCRIPTION
  Stages (run in this order, all by default):
    fetch  clone the pinned sources (repos.txt) into <SourceDir> and apply
           patches\<name>.patch
    deps   gnu : install missing MSYS2 packages, build DART & co. from source
           msvc: install the vcpkg manifest (vcpkg.json)
    build  configure / build / install every Gazebo library into <InstallDir>\<toolchain>
    dist   create the portable package <DistDir>\<toolchain>\gz-sim-harmonic-8.15.0
           (runtime files only + every non-system DLL they need)

  Paths are configured in toolchain.config.ps1.

.EXAMPLE
  .\build.ps1 -Toolchain gnu
.EXAMPLE
  .\build.ps1 -Toolchain msvc -Stages build,dist -Only gz-sim
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][ValidateSet('gnu', 'msvc')][string]$Toolchain,
  [ValidateSet('fetch', 'deps', 'build', 'dist')][string[]]$Stages = @('fetch', 'deps', 'build', 'dist'),
  # Restrict the deps/build stage to these package names.
  [string[]]$Only,
  [ValidateSet('Release', 'RelWithDebInfo', 'Debug')][string]$Config = 'Release',
  # Delete the build trees of the selected packages before building.
  [switch]$Clean,
  # dist: also keep the versioned plugin file names (libgz-sim8-*-system.dll,
  # gz-physics7-*-plugin.dll). By default only the unversioned names used by
  # SDF files are packaged.
  [switch]$KeepVersionedPlugins
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$PatchDir = $PSScriptRoot
$RootDir = (Resolve-Path (Join-Path $PatchDir '..\..')).Path
. (Join-Path $PatchDir 'toolchain.config.ps1')

$HarmonicVersion = Split-Path $PatchDir -Leaf  # harmonic-8.15.0

function Resolve-RootPath([string]$p) {
  if ([IO.Path]::IsPathRooted($p)) { return $p }
  return (Join-Path $RootDir $p)
}

$SrcDir = Resolve-RootPath $Cfg.SourceDir
$BuildRoot = Join-Path (Resolve-RootPath $Cfg.BuildDir) $Toolchain
$Prefix = Join-Path (Resolve-RootPath $Cfg.InstallDir) $Toolchain
$DistDir = Join-Path (Join-Path (Resolve-RootPath $Cfg.DistDir) $Toolchain) "gz-sim-$HarmonicVersion"
$Jobs = if ($Cfg.Jobs -gt 0) { $Cfg.Jobs } else { [Environment]::ProcessorCount }

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
function Write-Step([string]$msg) { Write-Host "`n==== $msg" -ForegroundColor Cyan }

# Run a native command, stream its output and fail on a non-zero exit code.
function Invoke-Exe {
  param([Parameter(Mandatory = $true)][string]$Exe, [string[]]$Arguments = @())
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & $Exe @Arguments 2>&1 | ForEach-Object {
      if ($_ -is [System.Management.Automation.ErrorRecord]) { Write-Host "$($_.TargetObject)" } else { Write-Host "$_" }
    }
    $code = $LASTEXITCODE
  } finally { $ErrorActionPreference = $old }
  if ($code -ne 0) { throw "'$Exe $($Arguments -join ' ')' failed with exit code $code" }
}

function Read-Repos {
  Get-Content (Join-Path $PatchDir 'repos.txt') | Where-Object { $_ -match '^\s*[^#\s]' } | ForEach-Object {
    $f = -split $_
    [pscustomobject]@{ Name = $f[0]; Url = $f[1]; Tag = $f[2]; Group = $f[3] }
  }
}

function Test-Selected([string]$name) { (-not $Only) -or ($Only -contains $name) }

# ---------------------------------------------------------------------------
# toolchain environment
# ---------------------------------------------------------------------------
$SysPath = "$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\WindowsPowerShell\v1.0"

function Enter-Gnu {
  $script:MsysBin = Join-Path $Cfg.Msys2Root "$($Cfg.Msys2Env)\bin"
  if (-not (Test-Path "$MsysBin\g++.exe")) { throw "g++ not found in $MsysBin (check Msys2Root/Msys2Env)" }
  # A clean PATH keeps CMake from picking up libraries of other toolchains.
  $env:PATH = "$Prefix\bin;$MsysBin;$SysPath"
  $env:CC = 'gcc'; $env:CXX = 'g++'
  $script:CMake = "$MsysBin\cmake.exe"
  $script:CommonCMakeArgs = @(
    '-G', 'Ninja',
    "-DCMAKE_MAKE_PROGRAM=$MsysBin\ninja.exe",
    "-DPython3_EXECUTABLE=$MsysBin\python.exe"
  )
  $script:RuntimeDllDirs = @("$Prefix\bin", $MsysBin)
}

function Enter-Msvc {
  $vs = $Cfg.VsInstall
  if (-not $vs) {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  }
  if (-not $vs -or -not (Test-Path "$vs\VC\Auxiliary\Build\vcvars64.bat")) { throw "Visual Studio with C++ tools not found (set VsInstall)" }
  $script:VsDir = $vs

  # Import vcvars64 on top of a clean PATH (no MSYS2 / other compilers).
  $vsInstaller = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer"
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $envDump = cmd /c "set PATH=$vsInstaller;$SysPath&& `"$vs\VC\Auxiliary\Build\vcvars64.bat`" >nul 2>nul && set" 2>$null
  $code = $LASTEXITCODE
  $ErrorActionPreference = $old
  if ($code -ne 0) { throw 'vcvars64.bat failed' }
  foreach ($line in $envDump) {
    if ($line -match '^([^=]+)=(.*)$') { Set-Item -Path "env:$($Matches[1])" -Value $Matches[2] }
  }
  Remove-Item env:CC, env:CXX -ErrorAction SilentlyContinue

  $script:VcpkgRoot = if ($Cfg.VcpkgRoot) { $Cfg.VcpkgRoot } else { "$vs\VC\vcpkg" }
  $script:VcpkgInstalled = Join-Path $BuildRoot 'vcpkg_installed'
  $triplet = $Cfg.VcpkgTriplet
  $vcpkgPrefix = Join-Path $VcpkgInstalled $triplet
  $env:PATH = "$Prefix\bin;$vcpkgPrefix\bin;$vcpkgPrefix\tools\protobuf;$vcpkgPrefix\tools\pkgconf;$env:PATH"

  $script:CMake = (Get-Command cmake.exe).Source
  $script:CommonCMakeArgs = @(
    '-G', 'Ninja',
    '-DCMAKE_C_COMPILER=cl', '-DCMAKE_CXX_COMPILER=cl',
    "-DCMAKE_TOOLCHAIN_FILE=$VcpkgRoot\scripts\buildsystems\vcpkg.cmake",
    '-DVCPKG_MANIFEST_MODE=OFF',
    "-DVCPKG_INSTALLED_DIR=$VcpkgInstalled",
    "-DVCPKG_TARGET_TRIPLET=$triplet",
    '-DVCPKG_APPLOCAL_DEPS=OFF',
    "-DPKG_CONFIG_EXECUTABLE=$vcpkgPrefix\tools\pkgconf\pkgconf.exe",
    "-DPython3_EXECUTABLE=$($Cfg.Python)"
  )
  $redist = Get-ChildItem "$vs\VC\Redist\MSVC" -Directory | Where-Object { $_.Name -match '^\d' } |
    Sort-Object { [version]$_.Name } | Select-Object -Last 1
  $crt = Get-ChildItem "$($redist.FullName)\x64" -Directory -Filter 'Microsoft.VC*.CRT' | Select-Object -First 1
  $script:RuntimeDllDirs = @("$Prefix\bin", "$vcpkgPrefix\bin", $crt.FullName)
}

# ---------------------------------------------------------------------------
# stage: fetch
# ---------------------------------------------------------------------------
function Invoke-Fetch {
  $GitExe = (Get-Command $Cfg.Git).Source
  New-Item -ItemType Directory -Force $SrcDir | Out-Null
  foreach ($r in Read-Repos) {
    if ($Toolchain -eq 'msvc' -and $r.Group -eq 'gnu') { continue }
    $dir = Join-Path $SrcDir $r.Name
    if (Test-Path $dir) {
      Write-Host "[fetch] $($r.Name): already present, skipped"
      continue
    }
    Write-Step "fetch $($r.Name) @ $($r.Tag)"
    Invoke-Exe $GitExe @('-c', 'advice.detachedHead=false', 'clone', '--quiet', '--depth', '1',
      '--branch', $r.Tag, '--config', 'core.autocrlf=false', $r.Url, $dir)
    $patch = Join-Path $PatchDir "patches\$($r.Name).patch"
    if (Test-Path $patch) {
      Write-Host "[fetch] applying $patch"
      Invoke-Exe $GitExe @('-C', $dir, 'apply', '--whitespace=nowarn', $patch)
    }
  }
}

# ---------------------------------------------------------------------------
# CMake package build
# ---------------------------------------------------------------------------
function Invoke-CMakePackage {
  param([string]$Name, [string]$SourceSubdir = '', [string[]]$Options = @())
  $src = Join-Path $SrcDir $Name
  if ($SourceSubdir) { $src = Join-Path $src $SourceSubdir }
  $bld = Join-Path $BuildRoot $Name
  if ($Clean -and (Test-Path $bld)) { Remove-Item -Recurse -Force $bld }
  Write-Step "build $Name ($Toolchain, $Config)"
  $cmakeArgs = @('-S', $src, '-B', $bld) + $CommonCMakeArgs + @(
    "-DCMAKE_BUILD_TYPE=$Config",
    "-DCMAKE_INSTALL_PREFIX=$Prefix",
    "-DCMAKE_PREFIX_PATH=$Prefix",
    '-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
    '-DBUILD_TESTING=OFF',
    '-DBUILD_DOCS=OFF'
  ) + $Options
  Invoke-Exe $CMake $cmakeArgs
  # Retry: ninja only rebuilds what failed. Guards against sporadic compiler
  # crashes (GCC internal compiler errors / cl.exe access violations were seen
  # under heavy parallel load); real compile errors still fail every attempt.
  for ($attempt = 1; ; $attempt++) {
    try { Invoke-Exe $CMake @('--build', $bld, '--parallel', "$Jobs"); break }
    catch {
      if ($attempt -ge 3) { throw }
      Write-Warning "build of $Name failed (attempt $attempt), retrying"
    }
  }
  Invoke-Exe $CMake @('--install', $bld)
}

# Options shared by all Gazebo libraries.
$GzOptions = @(
  '-DGZ_ENABLE_RELOCATABLE_INSTALL=ON',
  '-DSKIP_PYBIND11=ON',
  '-DSKIP_SWIG=ON',
  '-DENABLE_PROFILER=OFF'
)

# Per package options, in build order.
$GzPackages = [ordered]@{
  'gz-cmake'      = @()
  'gz-utils'      = @('-DGZ_UTILS_VENDOR_CLI11=ON')
  'gz-math'       = @()
  'gz-plugin'     = @()
  # av (ffmpeg) is only used by video recording / GUI.
  'gz-common'     = @('-DSKIP_av=ON', '-DGZ_COMMON_WITHOUT_GDAL=ON', '-DGZ_PROFILER_REMOTERY=OFF')
  'sdformat'      = @('-DUSE_INTERNAL_URDF=ON')
  'gz-msgs'       = @()
  'gz-transport'  = @()
  'gz-fuel-tools' = @()
  'gz-physics'    = @()
  'gz-sensors'    = @('-DGZ_SENSORS_WITHOUT_RENDERING=ON')
  'gz-sim'        = @('-DGZ_SIM_HEADLESS=ON')
}

# ---------------------------------------------------------------------------
# stage: deps
# ---------------------------------------------------------------------------
function Invoke-DepsGnu {
  $pkgPrefix = "mingw-w64-$($Cfg.Msys2Env)-x86_64-"
  if ($Cfg.Msys2Env -eq 'ucrt64') { $pkgPrefix = 'mingw-w64-ucrt-x86_64-' }
  elseif ($Cfg.Msys2Env -eq 'clang64') { $pkgPrefix = 'mingw-w64-clang-x86_64-' }
  $wanted = Get-Content (Join-Path $PatchDir 'msys2-packages.txt') |
    Where-Object { $_ -match '^\s*[^#\s]' } | ForEach-Object { $pkgPrefix + $_.Trim() }
  $pacman = Join-Path $Cfg.Msys2Root 'usr\bin\pacman.exe'
  $installed = & $pacman -Qq
  $missing = @($wanted | Where-Object { $installed -notcontains $_ })
  if ($missing.Count -gt 0) {
    if (-not $Cfg.Msys2AutoInstall) { throw "Missing MSYS2 packages: $($missing -join ' ')" }
    Write-Step "pacman -S $($missing -join ' ')"
    Invoke-Exe $pacman (@('-S', '--needed', '--noconfirm') + $missing)
  }

  # DART and its dependencies that MSYS2 does not package. All static, like
  # the vcpkg dartsim port (DART does not support being a Windows DLL).
  $static = @('-DBUILD_SHARED_LIBS=OFF')
  $deps = [ordered]@{
    'libccd'          = $static + @('-DENABLE_DOUBLE_PRECISION=ON', '-DBUILD_DOCUMENTATION=OFF')
    'fcl'             = $static + @('-DFCL_WITH_OCTOMAP=OFF', '-DFCL_BUILD_TESTS=OFF', '-DFCL_STATIC_LIBRARY=ON')
    'console_bridge'  = $static
    'urdfdom_headers' = @()
    'urdfdom'         = $static + @('-DBUILD_TINYXML2=OFF')
    'dart'            = $static + @(
      '-DDART_BUILD_DARTPY=OFF', '-DDART_BUILD_GUI_OSG=OFF', '-DDART_SKIP_DOXYGEN=ON',
      '-DDART_SKIP_IPOPT=ON', '-DDART_SKIP_NLOPT=ON', '-DDART_SKIP_pagmo=ON', '-DDART_SKIP_spdlog=ON',
      '-DDART_SKIP_GLUT=ON', '-DDART_SKIP_OPENGL=ON', '-DDART_SKIP_octomap=ON', '-DCMAKE_DISABLE_FIND_PACKAGE_spdlog=ON',
      '-DDART_TREAT_WARNINGS_AS_ERRORS=OFF', '-DDART_VERBOSE=ON',
      '-DCMAKE_REQUIRE_FIND_PACKAGE_BULLET=ON', '-DCMAKE_REQUIRE_FIND_PACKAGE_ODE=ON',
      '-DCMAKE_REQUIRE_FIND_PACKAGE_tinyxml2=ON', '-DCMAKE_REQUIRE_FIND_PACKAGE_urdfdom=ON',
      '-DCMAKE_DISABLE_FIND_PACKAGE_Python3=ON')
  }
  foreach ($name in $deps.Keys) {
    if (Test-Selected $name) { Invoke-CMakePackage -Name $name -Options $deps[$name] }
  }
}

function Invoke-DepsMsvc {
  $vcpkg = Join-Path $VcpkgRoot 'vcpkg.exe'
  Write-Step "vcpkg install ($($Cfg.VcpkgTriplet))"
  $env:VCPKG_ROOT = $VcpkgRoot
  Invoke-Exe $vcpkg @('install', "--x-manifest-root=$PatchDir", "--x-install-root=$VcpkgInstalled",
    "--triplet=$($Cfg.VcpkgTriplet)", "--host-triplet=$($Cfg.VcpkgTriplet)")
}

# ---------------------------------------------------------------------------
# stage: build
# ---------------------------------------------------------------------------
function Invoke-Build {
  foreach ($name in $GzPackages.Keys) {
    if (Test-Selected $name) {
      Invoke-CMakePackage -Name $name -Options ($GzOptions + $GzPackages[$name])
    }
  }
}

# ---------------------------------------------------------------------------
# stage: dist
# ---------------------------------------------------------------------------
function Get-DllImports([string]$file) {
  # Minimal PE import table reader (no objdump / dumpbin needed).
  $bytes = [IO.File]::ReadAllBytes($file)
  $pe = [BitConverter]::ToInt32($bytes, 0x3C)
  $numSections = [BitConverter]::ToUInt16($bytes, $pe + 6)
  $optSize = [BitConverter]::ToUInt16($bytes, $pe + 20)
  $opt = $pe + 24
  $magic = [BitConverter]::ToUInt16($bytes, $opt)
  $dirOffset = if ($magic -eq 0x20B) { $opt + 112 } else { $opt + 96 }
  $importRva = [BitConverter]::ToUInt32($bytes, $dirOffset + 8)
  $delayRva = [BitConverter]::ToUInt32($bytes, $dirOffset + 13 * 8)
  $secTable = $opt + $optSize
  $sections = for ($i = 0; $i -lt $numSections; $i++) {
    $s = $secTable + 40 * $i
    [pscustomobject]@{
      Va = [BitConverter]::ToUInt32($bytes, $s + 12); Size = [BitConverter]::ToUInt32($bytes, $s + 8)
      Raw = [BitConverter]::ToUInt32($bytes, $s + 20); RawSize = [BitConverter]::ToUInt32($bytes, $s + 16)
    }
  }
  function ToOffset([uint32]$rva) {
    foreach ($s in $sections) {
      $len = [Math]::Max($s.Size, $s.RawSize)
      if ($rva -ge $s.Va -and $rva -lt $s.Va + $len) { return [int]($rva - $s.Va + $s.Raw) }
    }
    return -1
  }
  function ReadName([int]$off) {
    $end = $off; while ($bytes[$end] -ne 0) { $end++ }
    [Text.Encoding]::ASCII.GetString($bytes, $off, $end - $off)
  }
  $names = New-Object System.Collections.Generic.List[string]
  if ($importRva) {
    $off = ToOffset $importRva
    while ($off -ge 0) {
      $nameRva = [BitConverter]::ToUInt32($bytes, $off + 12)
      if ($nameRva -eq 0) { break }
      $names.Add((ReadName (ToOffset $nameRva))); $off += 20
    }
  }
  if ($delayRva) {
    $off = ToOffset $delayRva
    while ($off -ge 0) {
      $nameRva = [BitConverter]::ToUInt32($bytes, $off + 4)
      if ($nameRva -eq 0) { break }
      $names.Add((ReadName (ToOffset $nameRva))); $off += 32
    }
  }
  return $names
}

function Invoke-Dist {
  Write-Step "dist -> $DistDir"
  if (Test-Path $DistDir) { Remove-Item -Recurse -Force $DistDir }
  New-Item -ItemType Directory -Force "$DistDir\bin" | Out-Null

  # 1. runtime files of the install prefix (no headers, import libs, cmake/pkgconfig files)
  $skipExt = @('.a', '.lib', '.h', '.hh', '.hpp', '.hxx', '.inl', '.cmake', '.pc', '.pdb', '.exp', '.ilk')
  $skipDirs = @('include', 'lib\cmake', 'lib\pkgconfig', 'share\cmake', 'share\pkgconfig', 'share\doc',
    'share\dart', 'share\fcl', 'share\ccd', 'share\console_bridge', 'share\urdfdom', 'share\urdfdom_headers',
    'CMake', 'lib\urdfdom', 'share\gz\gz-cmake3')
  Get-ChildItem -Recurse -File $Prefix | ForEach-Object {
    $rel = $_.FullName.Substring($Prefix.Length + 1)
    foreach ($d in $skipDirs) { if ($rel.StartsWith("$d\", [StringComparison]::OrdinalIgnoreCase)) { return } }
    if ($skipExt -contains $_.Extension.ToLowerInvariant()) { return }
    if ($_.Name -like '*.dll.a') { return }
    # static-library-only third party executables/tools are not needed
    if ($rel -like 'bin\*' -and $_.Extension -eq '.exe' -and $_.Name -notlike 'gz-*') { return }
    # build-time code generators
    if ($_.Name -like '*_protoc_plugin.exe') { return }
    # native CLI tools (e.g. gz-transport topic/service) need the DLLs next to them
    if ($rel -like 'libexec\*' -and $_.Extension -eq '.exe') { $rel = "bin\$($_.Name)" }
    elseif ($rel -like 'lib\ruby\*' -or $rel -like 'lib\python\*') { return }
    $dst = Join-Path $DistDir $rel
    New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
    Copy-Item $_.FullName $dst
  }

  # 2. plugins: keep one copy of each (gz-cmake installs versioned + unversioned)
  if (-not $KeepVersionedPlugins) {
    foreach ($pd in @('lib\gz-sim-8\plugins', 'lib\gz-physics-7\engine-plugins')) {
      $dir = Join-Path $DistDir $pd
      if (-not (Test-Path $dir)) { continue }
      Get-ChildItem -File -Filter *.dll $dir | ForEach-Object {
        $unversioned = $_.Name -replace '^((?:lib)?gz-(?:sim|physics))\d+-', '$1-'
        if ($unversioned -ne $_.Name -and (Test-Path (Join-Path $dir $unversioned))) { Remove-Item $_.FullName }
      }
    }
  }

  # 3. every non-system DLL reachable from the binaries goes next to the exe
  $index = @{}
  foreach ($d in $RuntimeDllDirs) {
    Get-ChildItem -File -Filter *.dll $d -ErrorAction SilentlyContinue | ForEach-Object {
      if (-not $index.ContainsKey($_.Name.ToLowerInvariant())) { $index[$_.Name.ToLowerInvariant()] = $_.FullName }
    }
  }
  $present = @{}
  # Only DLLs next to the executables can satisfy imports of other modules.
  Get-ChildItem -File -Filter *.dll (Join-Path $DistDir 'bin') | ForEach-Object { $present[$_.Name.ToLowerInvariant()] = $true }
  $queue = New-Object System.Collections.Generic.Queue[string]
  Get-ChildItem -Recurse -File -Include *.dll, *.exe $DistDir | ForEach-Object { $queue.Enqueue($_.FullName) }
  $visited = @{}
  $missing = @{}
  $imported = @{}
  while ($queue.Count -gt 0) {
    $f = $queue.Dequeue()
    if ($visited.ContainsKey($f)) { continue }
    $visited[$f] = $true
    foreach ($imp in Get-DllImports $f) {
      $key = $imp.ToLowerInvariant()
      $imported[$key] = $true
      if ($key -like 'api-ms-win-*' -or $key -like 'ext-ms-*') { continue }
      if ($present.ContainsKey($key)) { continue }
      if ($index.ContainsKey($key)) {
        $dst = Join-Path "$DistDir\bin" $imp
        Copy-Item $index[$key] $dst
        $present[$key] = $true
        $queue.Enqueue($dst)
      } elseif ($key -match '^(lib|gz-)' -or -not (Test-Path (Join-Path "$env:SystemRoot\System32" $imp))) {
        $missing[$imp] = $f
      }
    }
  }
  foreach ($m in $missing.Keys) { Write-Warning "unresolved DLL $m (needed by $($missing[$m]))" }
  if ($missing.Count -gt 0) { throw "dist: $($missing.Count) unresolved DLL(s), the package would not run" }

  # 4. system / physics engine plugins are also installed to bin; drop those
  #    copies unless another module links against them
  Get-ChildItem -File -Filter *.dll (Join-Path $DistDir 'bin') |
    Where-Object { $_.Name -match '^(lib)?gz-(sim\d+-.+-system|physics\d+-.+-plugin)\.dll$' } |
    Where-Object { -not $imported.ContainsKey($_.Name.ToLowerInvariant()) } |
    ForEach-Object { Remove-Item $_.FullName }

  # 5. GNU: strip symbol tables
  if ($Toolchain -eq 'gnu') {
    $strip = Join-Path $MsysBin 'strip.exe'
    Get-ChildItem -Recurse -File -Include *.dll, *.exe $DistDir | ForEach-Object {
      Invoke-Exe $strip @('--strip-unneeded', $_.FullName)
    }
  }

  $size = (Get-ChildItem -Recurse -File $DistDir | Measure-Object -Sum Length).Sum
  Write-Host ("[dist] {0} files, {1:N1} MB" -f (Get-ChildItem -Recurse -File $DistDir).Count, ($size / 1MB))
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
# The toolchain environment is changed in-process; restore it afterwards so
# the script can be run repeatedly from the same PowerShell session.
$savedEnv = Get-ChildItem env: | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Value = $_.Value } }
try {
  if ($Stages -contains 'fetch') { Invoke-Fetch }
  if ($Toolchain -eq 'gnu') { Enter-Gnu } else { Enter-Msvc }
  New-Item -ItemType Directory -Force $BuildRoot, $Prefix | Out-Null
  if ($Stages -contains 'deps') { if ($Toolchain -eq 'gnu') { Invoke-DepsGnu } else { Invoke-DepsMsvc } }
  if ($Stages -contains 'build') { Invoke-Build }
  if ($Stages -contains 'dist') { Invoke-Dist }
} finally {
  Get-ChildItem env: | Where-Object { $savedEnv.Name -notcontains $_.Name } | ForEach-Object { Remove-Item "env:$($_.Name)" }
  foreach ($e in $savedEnv) { Set-Item -Path "env:$($e.Name)" -Value $e.Value }
}
Write-Host "`nDone ($Toolchain): $($Stages -join ', ')" -ForegroundColor Green
