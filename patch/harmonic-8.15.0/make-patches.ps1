<#
.SYNOPSIS
  Regenerate patches\<name>.patch from the working trees in <SourceDir>.
  Every change relative to the pinned tag (including new files) is recorded;
  repositories without changes get their patch removed.
#>
[CmdletBinding()]
param([string[]]$Only)

$ErrorActionPreference = 'Stop'
$PatchDir = $PSScriptRoot
$RootDir = (Resolve-Path (Join-Path $PatchDir '..\..')).Path
. (Join-Path $PatchDir 'toolchain.config.ps1')
$SrcDir = if ([IO.Path]::IsPathRooted($Cfg.SourceDir)) { $Cfg.SourceDir } else { Join-Path $RootDir $Cfg.SourceDir }
$out = Join-Path $PatchDir 'patches'
New-Item -ItemType Directory -Force $out | Out-Null

Get-Content (Join-Path $PatchDir 'repos.txt') | Where-Object { $_ -match '^\s*[^#\s]' } | ForEach-Object {
  $name = (-split $_)[0]
  if ($Only -and $Only -notcontains $name) { return }
  $dir = Join-Path $SrcDir $name
  if (-not (Test-Path "$dir\.git")) { return }
  $patch = Join-Path $out "$name.patch"
  # intent-to-add makes untracked files show up in the diff
  & $Cfg.Git -C $dir add --all --intent-to-add
  # git writes the file itself: piping through PowerShell would drop the CR of
  # upstream files with CRLF line endings and break the patch
  $tmp = "$patch.tmp"
  & $Cfg.Git -C $dir -c core.autocrlf=false diff --binary --no-color --no-ext-diff "--output=$tmp" HEAD
  if ($LASTEXITCODE -ne 0) { throw "git diff failed in $dir" }
  if ((Get-Item $tmp).Length -gt 0) {
    Move-Item -Force $tmp $patch
    Write-Host "wrote $patch"
  } else {
    Remove-Item $tmp
    if (Test-Path $patch) {
      Remove-Item $patch
      Write-Host "removed $patch (no changes)"
    }
  }
}
