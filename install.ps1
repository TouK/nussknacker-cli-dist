#Requires -Version 5.1
# Installs nu-cli, the Nussknacker command line client, as a single executable - no Node, no npm.
#
#   irm https://raw.githubusercontent.com/TouK/nussknacker-cli-dist/main/install.ps1 | iex
#
# With arguments, the script has to become a scriptblock first - `iex` on a string has nowhere to put them:
#
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/TouK/nussknacker-cli-dist/main/install.ps1))) -Snapshot
#
# The counterpart of install.sh, and deliberately a second script rather than a clever one: Windows has no
# POSIX shell, and every step here - gunzip, sha256, atomic replace - is a different tool from the one the
# shell script reaches for. What the two do share is the layout they read, so anything published for one is
# installable by the other.
#
# Downloading here rather than through a browser also avoids the mark of the web: a browser tags what it
# saves, and SmartScreen then asks about every run. Invoke-WebRequest writing a file does not tag it.
[CmdletBinding()]
param(
    # Exact version to install. Without it, whichever version the channel's marker names.
    [string] $Version,
    # The newest snapshot of master instead of the newest release. Asked for rather than given by default,
    # since a snapshot is whatever master was at the time.
    [switch] $Snapshot,
    # Directory to install into. $env:NU_CLI_PREFIX does the same.
    [string] $Prefix,
    # Override the target. Detection only ever yields windows-x64, which is the one Windows build
    # published; this is the escape hatch for whatever gets published next.
    [string] $Target,
    # Add the install directory to the user's PATH. Off by default: this script installs a file, and
    # changing the environment is a separate decision.
    [switch] $AddToPath,
    # Ask nothing and take the defaults, for a script or an unattended machine.
    [switch] $Yes,
    [switch] $Help
)

$ErrorActionPreference = 'Stop'

# What went wrong, with room around it, and the line to copy out underneath. PowerShell colours by name and
# leaves them out when its output is redirected, so there is nothing to detect here.
function Problem([string] $text) {
    Write-Host ""
    Write-Host $text -ForegroundColor Red
    Write-Host ""
}
function CommandHint([string] $text) {
    Write-Host "    $text" -ForegroundColor Cyan
}

# Nothing is asked where there is nobody to answer - a scheduled task, a build agent, a shell reading this
# from a pipe - and -Yes (or $env:NU_CLI_YES) says so outright.
$asking = -not ($Yes -or $env:NU_CLI_YES) -and [Environment]::UserInteractive -and -not [Console]::IsInputRedirected

function Confirm([string] $question) {
    if (-not $asking) { return $true }
    $answer = Read-Host "$question [Y/n]"
    return $answer -notmatch '^\s*n'
}

if ($Help) {
    @'
install.ps1 - install nu-cli, the Nussknacker command line client, as a single executable

  -Version <v>     version to install (default: the newest release)
  -Snapshot        the newest snapshot of master instead of the newest release
  -Prefix <dir>    where to put the binary (default: %LOCALAPPDATA%\Programs\nu-cli)
  -Target <name>   override the target (detection always says windows-x64)
  -AddToPath       add the install directory to the user PATH
  -Yes             ask nothing; take the defaults
  -Help

  $env:NU_CLI_REPO       the GitHub repository the builds are published to
  $env:NU_CLI_BASE_URL   its address, if not https://github.com/<NU_CLI_REPO>
  $env:NU_CLI_PREFIX     same as -Prefix
  $env:NU_CLI_YES        same as -Yes
'@ | Write-Host
    return
}

# Every build is a release of this repository, tagged with its version, and every file is an asset of it.
$repo = if ($env:NU_CLI_REPO) { $env:NU_CLI_REPO } else { 'TouK/nussknacker-cli-dist' }
$baseUrl = if ($env:NU_CLI_BASE_URL) { $env:NU_CLI_BASE_URL } else { "https://github.com/$repo" }

if (-not $Prefix) {
    $Prefix = if ($env:NU_CLI_PREFIX) { $env:NU_CLI_PREFIX } else { Join-Path $env:LOCALAPPDATA 'Programs\nu-cli' }
}

if (-not $Target) {
    # windows-x64 is the only Windows target published, and it is the right answer on ARM64 too: Windows
    # runs x64 binaries under emulation, and an ARM64 build of nothing is worse than an emulated one.
    $Target = 'windows-x64'
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
        Write-Host 'note: this is an ARM64 machine; the x64 build runs under Windows emulation.'
    }
}

# The windows build is published with the extension Windows needs; every other target is bare. -Target is
# the only way to ask for one of those from here, but asking for it has to work.
$binary = if ($Target -like 'windows*') { "nu-cli-$Target.exe" } else { "nu-cli-$Target" }
# What is published is the executable gzipped: under half the size, so that much less to download.
$archive = "$binary.gz"

# PS 5.1 negotiates TLS 1.0 by default, which the registry refuses; -bor rather than assignment so a
# machine configured for TLS 1.3 keeps it.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {
    # PowerShell 7 on a platform that manages this itself. Nothing to do, and not a reason to stop.
}

# Invoke-WebRequest renders a progress bar per chunk, which on 5.1 costs more time than the download of a
# 50 MB file does.
$progress = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'

$temp = Join-Path ([IO.Path]::GetTempPath()) ("nu-cli-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null

try {
    # ---- which version ---------------------------------------------------------------------------

    $named = [bool] $Version
    if (-not $named) {
        if ($Snapshot) {
            # A tiny asset on a release that carries nothing else, rewritten by every publish from master.
            $marker = "$baseUrl/releases/download/snapshot/latest.txt"
            try {
                $Version = (Invoke-WebRequest -UseBasicParsing -Uri $marker).Content.Trim()
            } catch {
                # What somebody sees when the only builds published so far came from a branch: those exist,
                # they are just not what -Snapshot means. The file this reads is nobody's business - where to
                # look instead is.
                Problem 'There is no snapshot of master to install yet.'
                Write-Host 'Builds made from a branch are published under their own version:'
                CommandHint "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/$repo/main/install.ps1))) -Version <version>"
                Write-Host ""
                Write-Host "Which versions there are: $baseUrl/releases" -ForegroundColor DarkGray
                Write-Host ""
                throw "no snapshot to install"
            }
        } else {
            # `releases/latest` answers a redirect to `releases/tag/<version>`, so the released version can be
            # read from where it points - one request, and no API call to be rate-limited.
            $response = Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/releases/latest" -MaximumRedirection 0 `
                -ErrorAction SilentlyContinue
            $location = $response.Headers.Location
            if ($location -match '/releases/tag/(.+)$') {
                $Version = $Matches[1]
            } else {
                Problem 'Nothing has been released yet.'
                Write-Host 'For the newest build of master, ask for a snapshot:'
                CommandHint "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/$repo/main/install.ps1))) -Snapshot"
                Write-Host ""
                Write-Host 'A flag needs the scriptblock form: `irm ... | iex` has nowhere to pass it.' -ForegroundColor DarkGray
                Write-Host "Every build there is, released or not: $baseUrl/releases" -ForegroundColor DarkGray
                Write-Host ""
                throw "no release to install"
            }
        }
        if (-not $Version) { throw "install.ps1: the version could not be determined" }
    }

    # `releases/latest/download/...` where that is what was asked for: one redirect rather than two, and it
    # stays correct if a release is published between these two requests.
    $base = if ($Snapshot -or $named) { "$baseUrl/releases/download/$Version" } else { "$baseUrl/releases/latest/download" }

    # ---- what is about to happen -------------------------------------------------------------------

    # Asked for, so that the size is the one thing said about the download that is not a guess.
    $size = "size unknown"
    try {
        $head = Invoke-WebRequest -UseBasicParsing -Uri "$base/$archive" -Method Head
        $bytes = [int64] $head.Headers['Content-Length'][0]
        $size = "{0:N0} MB" -f [math]::Round($bytes / 1MB)
    } catch {
        # Not worth a word: the download says soon enough whether it is there.
    }

    Write-Host ""
    Write-Host "nu-cli $Version " -NoNewline
    Write-Host "($Target)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host ("  {0,-11} {1} " -f 'download', $archive) -NoNewline
    Write-Host "($size)" -ForegroundColor DarkGray
    Write-Host ("  {0,-11} {1}" -f 'from', $base)
    Write-Host ("  {0,-11} {1}" -f 'install to', (Join-Path $Prefix 'nu-cli.exe'))
    Write-Host ""

    if (-not (Confirm 'Download it?')) { throw "nothing was downloaded." }

    # ---- download, check, install ----------------------------------------------------------------

    $archivePath = Join-Path $temp $archive
    try {
        Invoke-WebRequest -UseBasicParsing -Uri "$base/$archive" -OutFile $archivePath
    } catch {
        throw ("install.ps1: could not download $archive of version $Version. " +
            "Check the version, and that this target was published.")
    }
    $sumsPath = Join-Path $temp 'SHA256SUMS'
    Invoke-WebRequest -UseBasicParsing -Uri "$base/SHA256SUMS" -OutFile $sumsPath

    # Verified before it is unpacked, and on the bytes that crossed the network rather than on something
    # derived from them.
    # Matched in this scope rather than inside a Where-Object: -match fills $Matches where it runs, and a
    # pipeline's scriptblock is not here, so the capture would be read back empty.
    $pattern = "^([0-9a-fA-F]{64})\s+$([regex]::Escape($archive))$"
    $expected = $null
    foreach ($sum in (Get-Content -LiteralPath $sumsPath)) {
        if ($sum -match $pattern) { $expected = $Matches[1]; break }
    }
    if (-not $expected) { throw "install.ps1: SHA256SUMS of version $Version says nothing about $archive" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash
    if ($actual -ne $expected.ToUpperInvariant()) {
        throw ("install.ps1: checksum mismatch for ${archive}: got $actual, expected $expected. " +
            "The download is not what was published - do not run it.")
    }

    # Said out loud, because a checksum that is only checked in silence might as well not be checked.
    Write-Host "  sha256 ok " -ForegroundColor Green -NoNewline
    Write-Host "$($actual.Substring(0, 16).ToLowerInvariant())…" -ForegroundColor DarkGray

    # gzip without a gzip: GZipStream ships with .NET, so there is nothing to install first. The published
    # archive holds one file and carries no name for it, which is why the name is built above.
    $binaryPath = Join-Path $temp $binary
    $source = [IO.File]::OpenRead($archivePath)
    try {
        $gzip = New-Object IO.Compression.GZipStream($source, [IO.Compression.CompressionMode]::Decompress)
        try {
            $destination = [IO.File]::Create($binaryPath)
            try { $gzip.CopyTo($destination) } finally { $destination.Dispose() }
        } finally { $gzip.Dispose() }
    } finally { $source.Dispose() }

    # Where it goes is asked rather than announced, and what is asked about is the whole path, the file name
    # included. Read-Host cannot put the default into the line the way readline does for the shell script, so
    # it goes in brackets and enter accepts it.
    $destination = Join-Path $Prefix 'nu-cli.exe'
    if ($asking) {
        Write-Host ""
        $answer = (Read-Host "Install to [$destination]").Trim()
        if ($answer) {
            # A directory was meant if it says so - it exists, or it ends in a separator - and then the file
            # keeps its name. Anything else is the path of the file itself.
            if ($answer.EndsWith('\') -or $answer.EndsWith('/') -or (Test-Path -LiteralPath $answer -PathType Container)) {
                $destination = Join-Path $answer 'nu-cli.exe'
            } else {
                $destination = $answer
            }
        }
    }

    $Prefix = Split-Path -Parent $destination
    New-Item -ItemType Directory -Path $Prefix -Force | Out-Null
    $installed = $destination
    try {
        Move-Item -LiteralPath $binaryPath -Destination $installed -Force
    } catch {
        # Windows locks a running executable rather than letting it be replaced underneath, and an MCP
        # server started by an editor is exactly the nu-cli somebody forgets is running.
        throw ("install.ps1: could not replace ${installed}. Close anything running nu-cli - an MCP server " +
            "in an editor counts - and run this again.")
    }

    Write-Host ""
    Write-Host "installed " -ForegroundColor Green -NoNewline
    Write-Host $installed

    if ($AddToPath) {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if (($userPath -split ';') -notcontains $Prefix) {
            $updated = if ($userPath) { $userPath.TrimEnd(';') + ';' + $Prefix } else { $Prefix }
            [Environment]::SetEnvironmentVariable('Path', $updated, 'User')
            Write-Host ""
            Write-Host "added $Prefix to your user PATH - open a new terminal for it to take effect"
        }
    } elseif (($env:PATH -split ';') -notcontains $Prefix) {
        Write-Host ""
        Write-Host "$Prefix is not on your PATH." -ForegroundColor Yellow
        Write-Host 'Run this again with -AddToPath, or call the binary by its full path.'
        Write-Host ""
    }

    # Runs it rather than trusting it, and shows what it says: the version out of the binary is the only proof
    # that what was installed is what was asked for.
    $reported = & $installed --version 2> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "nu-cli" -ForegroundColor DarkGray -NoNewline
        Write-Host " says it is $reported"
        Write-Host ""
        if ($reported -ne $Version) {
            Write-Host "note: that is not $Version, which is what this installed." -ForegroundColor DarkGray
            Write-Host ""
        }
    } else {
        Problem "$installed did not run."
        Write-Host 'A binary fetched with -Target for another platform is not expected to run here.' -ForegroundColor DarkGray
        Write-Host ""
    }
} finally {
    # Covers every exit, so a failed download leaves nothing behind.
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    $ProgressPreference = $progress
}
