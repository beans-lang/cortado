# Install the cortado command line for the current user.
#
#   irm https://github.com/beans-lang/cortado/releases/latest/download/cortado-install.ps1 | iex
#
# Only built-in PowerShell is used — Invoke-WebRequest to download, Get-FileHash
# to verify, Expand-Archive to unpack. No jq, no Python, no Git, and no
# administrator rights: everything lands under the user's LOCALAPPDATA.
#
# Nothing is installed until the download has been checksummed, unpacked into a
# staging directory, and the binary in it has answered `--version`.

[CmdletBinding()]
param(
    [string] $Version,
    [string] $Prefix,
    [string] $Target,
    [switch] $WithSkia,
    [switch] $Force,
    [switch] $NoModifyPath,
    [switch] $Help
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Repo = if ($env:CORTADO_INSTALL_REPO) { $env:CORTADO_INSTALL_REPO } else { 'beans-lang/cortado' }
$ManifestName = 'cortado-release-manifest.tsv'

function Write-Note([string] $Message) { Write-Host "cortado: $Message" }
function Die([string] $Message) { Write-Error "cortado: error: $Message"; exit 1 }

# `irm ... | iex` gives the script no parameters, so the environment variables
# are the only way to configure that entry point.
if (-not $Version -and $env:CORTADO_VERSION) { $Version = $env:CORTADO_VERSION }
if (-not $Prefix  -and $env:CORTADO_HOME)    { $Prefix  = $env:CORTADO_HOME }
if (-not $Target  -and $env:CORTADO_TARGET)  { $Target  = $env:CORTADO_TARGET }
if (-not $WithSkia -and $env:CORTADO_WITH_SKIA) { $WithSkia = $true }

if ($Help) {
    @'
usage: cortado-install.ps1 [-Version <v>] [-Prefix <dir>] [-Target <triple>]
                           [-WithSkia] [-Force] [-NoModifyPath]

  -Version       install this release instead of the latest (e.g. 0.1.1)
  -Prefix        install here instead of $env:LOCALAPPDATA\cortado
  -Target        force a Beans target instead of detecting one
  -WithSkia      also install the prebuilt shared renderer (~20MB)
  -Force         reinstall even when this version is already installed
  -NoModifyPath  do not touch the user PATH
'@ | Write-Host
    exit 0
}

if (-not $Prefix) { $Prefix = Join-Path $env:LOCALAPPDATA 'cortado' }
if (-not [System.IO.Path]::IsPathRooted($Prefix)) {
    Die "-Prefix must be an absolute path, not '$Prefix'"
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("cortado-install-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $work -Force | Out-Null

try {
    # ------------------------------------------------------------------ target
    if (-not $Target) {
        # Beans has no 32-bit Windows release for cortado, and the arm64 package
        # is named separately rather than run through emulation.
        switch ($env:PROCESSOR_ARCHITECTURE) {
            'AMD64' { $Target = 'x86_64-pc-windows-msvc' }
            'ARM64' { $Target = 'aarch64-pc-windows-msvc' }
        }
    }

    # ---------------------------------------------------------------- manifest
    $baseIsOurs = $false
    $base = $env:CORTADO_INSTALL_BASE_URL
    if (-not $base) {
        $baseIsOurs = $true
        if ($Version) { $base = "https://github.com/$Repo/releases/download/v$Version" }
        else          { $base = "https://github.com/$Repo/releases/latest/download" }
    }
    $manifestUrl = if ($env:CORTADO_INSTALL_MANIFEST) { $env:CORTADO_INSTALL_MANIFEST }
                   else { "$base/$ManifestName" }

    $manifestPath = Join-Path $work 'manifest.tsv'
    try {
        if ($manifestUrl -match '^https?://') {
            Invoke-WebRequest -Uri $manifestUrl -OutFile $manifestPath -UseBasicParsing
        } else {
            Copy-Item -LiteralPath $manifestUrl -Destination $manifestPath
        }
    } catch {
        Die "cannot download the release manifest from $manifestUrl"
    }

    $rows = @()
    foreach ($line in Get-Content -LiteralPath $manifestPath) {
        if ($line.StartsWith('#') -or -not $line.Trim()) { continue }
        $f = $line -split "`t"
        if ($f.Count -lt 7) { continue }
        $rows += , [pscustomobject]@{
            Version = $f[0]; Target = $f[1]; Os = $f[2]; Arch = $f[3]
            Kind = $f[4]; Asset = $f[5]; Sha256 = $f[6]
        }
    }

    $row = $rows | Where-Object { $_.Target -eq $Target -and $_.Kind -eq 'cli' } | Select-Object -First 1
    if (-not $row) {
        Write-Host "cortado: no released package matches this machine." -ForegroundColor Red
        Write-Host ""
        Write-Host "  architecture:  $env:PROCESSOR_ARCHITECTURE"
        Write-Host "  beans target:  $(if ($Target) { $Target } else { 'could not be determined' })"
        Write-Host ""
        Write-Host "Published targets:"
        $rows | Where-Object { $_.Kind -eq 'cli' } | ForEach-Object { Write-Host "  $($_.Target)" }
        Write-Host ""
        Write-Host "Pick one with -Target, or build from source:"
        Write-Host "  https://github.com/$Repo#installing"
        exit 1
    }

    $releaseVersion = $row.Version
    # Pin the rest of this install to the release the manifest named: `latest`
    # moves, and a release published mid-install 404s every URL under it.
    if ($baseIsOurs) { $base = "https://github.com/$Repo/releases/download/v$releaseVersion" }
    if ($Version -and $Version -ne $releaseVersion) {
        Die "the manifest at $manifestUrl publishes $releaseVersion, not $Version"
    }

    $skiaRow = $null
    if ($WithSkia) {
        $skiaRow = $rows | Where-Object { $_.Target -eq $Target -and $_.Kind -eq 'skia' } | Select-Object -First 1
        if (-not $skiaRow) {
            Die "no prebuilt shared renderer is published for $Target; install without -WithSkia"
        }
    }

    # -------------------------------------------------------- already installed
    $launcherPath = Join-Path $Prefix 'bin\cortado.cmd'
    if (-not $Force -and (Test-Path -LiteralPath $launcherPath)) {
        $installed = & $launcherPath --version 2>$null
        if ($installed -and ($installed -join ' ').Contains($releaseVersion)) {
            $engines = @(Get-ChildItem -Path (Join-Path $Prefix 'lib') -Filter '*cortado_skia_engine*' -ErrorAction SilentlyContinue)
            if (-not $WithSkia -or $engines.Count -gt 0) {
                Write-Note "cortado $releaseVersion is already installed in $Prefix"
                Write-Note "re-run with -Force to reinstall"
                exit 0
            }
        }
    }

    function Get-Asset([string] $name, [string] $expected) {
        $path = Join-Path $work $name
        Write-Note "downloading $name"
        try {
            if ($base -match '^https?://') {
                Invoke-WebRequest -Uri "$base/$name" -OutFile $path -UseBasicParsing
            } else {
                Copy-Item -LiteralPath (Join-Path $base $name) -Destination $path
            }
        } catch { Die "cannot download $base/$name" }
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
        if ($actual -ne $expected.ToLower()) {
            Die "checksum mismatch for $name`n  expected $expected`n  actual   $actual`nNothing was installed."
        }
        return $path
    }

    $archive = Get-Asset $row.Asset $row.Sha256
    Write-Note "checksum verified"

    $stage = Join-Path $work 'stage'
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    Expand-Archive -LiteralPath $archive -DestinationPath $stage -Force
    $unpacked = Get-ChildItem -Path $stage -Directory | Select-Object -First 1
    if (-not $unpacked) { Die "$($row.Asset) does not contain a package directory" }

    if ($WithSkia) {
        $skiaArchive = Get-Asset $skiaRow.Asset $skiaRow.Sha256
        $skiaStage = Join-Path $work 'skia'
        New-Item -ItemType Directory -Path $skiaStage -Force | Out-Null
        Expand-Archive -LiteralPath $skiaArchive -DestinationPath $skiaStage -Force
        $engine = Get-ChildItem -Path $skiaStage -Recurse -File -Filter '*cortado_skia_engine*' | Select-Object -First 1
        if (-not $engine) { Die "$($skiaRow.Asset) carries no engine library" }
        $libDir = Join-Path $unpacked.FullName 'lib'
        New-Item -ItemType Directory -Path $libDir -Force | Out-Null
        Copy-Item -LiteralPath $engine.FullName -Destination $libDir
        Write-Note "shared renderer staged"
    }

    # The staged binary has to answer before anything is moved into place, so a
    # corrupt or wrong-architecture download can never replace a working install.
    $stagedLauncher = Join-Path $unpacked.FullName 'bin\cortado.cmd'
    if (-not (Test-Path -LiteralPath $stagedLauncher)) {
        Die "$($row.Asset) has no bin\cortado.cmd; nothing was installed"
    }
    $staged = & $stagedLauncher --version 2>$null
    if (-not $staged) { Die "the downloaded cortado does not run on this machine; nothing was installed" }
    Write-Note "staged $($staged -join ' ')"

    # ----------------------------------------------------------------- install
    $parent = Split-Path -Parent $Prefix
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $previous = $null
    if (Test-Path -LiteralPath $Prefix) {
        $previous = "$Prefix.old-$PID"
        Move-Item -LiteralPath $Prefix -Destination $previous
    }
    try {
        Move-Item -LiteralPath $unpacked.FullName -Destination $Prefix
    } catch {
        if ($previous) { Move-Item -LiteralPath $previous -Destination $Prefix }
        Die "cannot install into $Prefix"
    }
    if ($previous) { Remove-Item -LiteralPath $previous -Recurse -Force -ErrorAction SilentlyContinue }

    # -------------------------------------------------------------------- PATH
    $binDir = Join-Path $Prefix 'bin'
    if (-not $NoModifyPath) {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if (-not $userPath) { $userPath = '' }
        $entries = $userPath -split ';' | Where-Object { $_ }
        if ($entries -notcontains $binDir) {
            [Environment]::SetEnvironmentVariable('Path', (($entries + $binDir) -join ';'), 'User')
            Write-Note "PATH updated for your user account"
        } else {
            Write-Note "PATH already contains $binDir"
        }
    }

    Write-Host ""
    Write-Note "installed cortado $releaseVersion into $Prefix"
    if ($WithSkia) {
        Write-Note "the shared renderer is in $Prefix\lib; cortado sets CORTADO_SKIA_LIBRARY for you"
    } else {
        Write-Note "the shared Skia renderer is not installed; add it with -WithSkia"
    }
    Write-Host ""
    Write-Host "    `$env:Path = `"$binDir;`$env:Path`""
    Write-Host ""
    & (Join-Path $binDir 'cortado.cmd') --version
    Write-Note "cortado needs beansc to build a project: https://github.com/beans-lang/beans"
    Write-Note "start one with 'cortado init myapp'"
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
