#Requires -Version 5.1
<#
    One-line installer for agentop on Windows.

      irm https://agentop.pimlabs.id/install.ps1 | iex

    Written against Windows PowerShell 5.1, which is what Windows 10 and 11
    ship, rather than PowerShell 7. `irm | iex` runs on a stock machine with
    nothing turned on, so this script cannot assume a newer runtime is there.
    That rules out the ternary operator and `??`; if you reach for one, test
    on 5.1 before it lands.

    Piped into `iex` there is no argv, so both knobs are environment
    variables, exactly as install.sh does it:

      $env:AGENTOP_VERSION     = "v0.11.0"   # default: the latest release
      $env:AGENTOP_INSTALL_DIR = "C:\tools"  # default: %LOCALAPPDATA%\agentop\bin
      $env:AGENTOP_NO_PATH     = "1"         # do not touch PATH

    This is a port of install.sh's rules, not a port of anybody else's
    installer. The rule that matters most: we do not install a binary whose
    checksum we have not verified. bun's PowerShell installer does not verify
    one at all, which is why it was read and then not copied.

    Everything the script defines has to be defined before it is used: `iex`
    evaluates this text top to bottom, so a function declared below its caller
    does not exist yet when the caller runs.
#>

$ErrorActionPreference = "Stop"

$Repo = "pimlabs/agentop"

function Write-Info {
    param([string]$Message)
    Write-Host "install.ps1: $Message"
}

function Stop-WithError {
    param([string]$Message)
    # `throw` rather than `exit`. Piped through `iex` this script runs in the
    # caller's own session, where `exit` closes their PowerShell window: a
    # failed install would take the terminal with it. A throw prints in red,
    # returns to the prompt, and still fails a CI step.
    throw "install.ps1: $Message"
}

function Publish-EnvironmentChange {
    <#
        Tell every running process that the environment changed. Without this
        the new PATH is invisible to everything already open, including the
        shell the user is standing in, and the install looks like it failed.
    #>
    if (-not ("AgentopNative.Win32" -as [type])) {
        Add-Type -Namespace AgentopNative -Name Win32 -MemberDefinition @"
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
"@
    }
    $HWND_BROADCAST = [IntPtr] 0xffff
    $WM_SETTINGCHANGE = 0x1a
    $SMTO_ABORTIFHUNG = 2
    $result = [UIntPtr]::Zero
    [AgentopNative.Win32]::SendMessageTimeout(
        $HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero,
        "Environment", $SMTO_ABORTIFHUNG, 5000, [ref] $result) | Out-Null
}

function Add-ToUserPath {
    param([string]$Directory)

    <#
        Written straight into HKCU:\Environment rather than through
        [Environment]::SetEnvironmentVariable. That API expands a REG_EXPAND_SZ
        PATH before writing it back, so an entry the user already had as
        %USERPROFILE%\... comes out as a literal path and stops following the
        variable it was written against. The registry API preserves the value
        kind, so read the kind and write the same one back.
    #>
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $true)
    if (-not $key) {
        Write-Info "warning: could not open HKCU:\Environment, so PATH was left alone. Add this directory yourself:"
        Write-Info "  $Directory"
        return
    }

    try {
        # DoNotExpandEnvironmentNames keeps %USERPROFILE% as written rather
        # than reading back a resolved copy we would then store.
        $current = $key.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        try {
            $kind = $key.GetValueKind("Path")
        } catch {
            # No user PATH yet, which is unusual but legal.
            $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
        }

        $entries = @($current -split ';' | Where-Object { $_ -ne "" })
        foreach ($entry in $entries) {
            if ($entry.TrimEnd('\') -ieq $Directory.TrimEnd('\')) {
                Write-Info "$Directory is already on your PATH."
                return
            }
        }

        $entries += $Directory
        $key.SetValue("Path", ($entries -join ';'), $kind)
        Write-Info "added $Directory to your user PATH."
    } finally {
        $key.Close()
    }

    Publish-EnvironmentChange

    # The broadcast above reaches processes that listen for it. This shell is
    # not one of them, so set it here too and the verification line below can
    # actually run.
    $env:PATH = "$env:PATH;$Directory"
}

# --- TLS ----------------------------------------------------------------
# Windows PowerShell 5.1 inherits the .NET Framework default, which on
# machines that have not been patched still negotiates TLS 1.0. GitHub refuses
# that, and the failure reads as "the underlying connection was closed", which
# names nothing a person can act on.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {
    # A newer runtime that no longer exposes the knob. Nothing to do.
}

# --- detect the architecture --------------------------------------------
# PROCESSOR_ARCHITECTURE describes the *process*, so a 32-bit PowerShell on
# 64-bit Windows reports x86 and would fetch the wrong archive.
# PROCESSOR_ARCHITEW6432 is set only in that case and describes the machine,
# so it wins when present.
$archRaw = $env:PROCESSOR_ARCHITEW6432
if (-not $archRaw) { $archRaw = $env:PROCESSOR_ARCHITECTURE }

switch ($archRaw) {
    "AMD64" { $arch = "amd64" }
    "ARM64" { $arch = "arm64" }
    default {
        Stop-WithError "this script does not support the architecture '$archRaw'. agentop ships amd64 and arm64 builds for Windows; download one by hand from https://github.com/$Repo/releases if yours differs."
    }
}

# --- version ------------------------------------------------------------
$version = $env:AGENTOP_VERSION
if (-not $version) {
    Write-Info "asking the GitHub API for the latest release..."
    # Deliberately NOT /releases/latest. That endpoint answers with the newest
    # release of ANY kind, and this repo publishes two tag series into one
    # releases page: v* for the binary and vscode-v* for the editor extension.
    # On 20 August 2026 vscode-v0.6.0 was newer than v0.11.0, and install.sh
    # spent that day asking for an archive named after the extension's tag.
    # /releases lists newest first, so take the first tag that names a binary.
    try {
        $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases?per_page=30" `
            -Headers @{ "User-Agent" = "agentop-install" } -UseBasicParsing
        foreach ($release in $releases) {
            if ($release.tag_name -match '^v[0-9]') {
                $version = $release.tag_name
                break
            }
        }
    } catch {
        Stop-WithError "could not read the release list from the GitHub API: $($_.Exception.Message). Set `$env:AGENTOP_VERSION = 'vX.Y.Z' and run this again."
    }
}
if (-not $version) {
    Stop-WithError "could not find a released agentop version through the GitHub API. Set `$env:AGENTOP_VERSION = 'vX.Y.Z' and run this again."
}

# goreleaser's name_template uses the version with no leading 'v', while the
# git tag and the release URL both carry one. Keep the two apart.
$versionNoTag = $version -replace '^v', ''

Write-Info "installing agentop $version for windows/$arch..."

$archiveName = "agentop_${versionNoTag}_windows_${arch}.zip"
$baseUrl = "https://github.com/$Repo/releases/download/$version"

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("agentop-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    $archivePath = Join-Path $tmp $archiveName
    $checksumPath = Join-Path $tmp "checksums.txt"

    try {
        Invoke-WebRequest -Uri "$baseUrl/$archiveName" -OutFile $archivePath -UseBasicParsing
        Invoke-WebRequest -Uri "$baseUrl/checksums.txt" -OutFile $checksumPath -UseBasicParsing
    } catch {
        Stop-WithError "download failed: $($_.Exception.Message). Check that $version is a published release at https://github.com/$Repo/releases."
    }

    # --- verify the checksum ---------------------------------------------
    # goreleaser publishes ONE combined checksums.txt for the whole release,
    # so filter it down to the line naming our archive before comparing.
    $expected = $null
    foreach ($line in Get-Content $checksumPath) {
        $parts = $line -split '\s+', 2
        if ($parts.Count -eq 2 -and $parts[1].Trim() -eq $archiveName) {
            $expected = $parts[0].Trim()
            break
        }
    }
    if (-not $expected) {
        Stop-WithError "checksums.txt has no line for $archiveName. The release may be incomplete; please report it at https://github.com/$Repo/issues."
    }

    # Get-FileHash returns uppercase and goreleaser writes lowercase.
    # PowerShell's -ne happens to be case-insensitive, which is exactly the
    # kind of thing a security check should not lean on silently.
    $actual = (Get-FileHash -Path $archivePath -Algorithm SHA256).Hash
    if ($actual.ToUpperInvariant() -cne $expected.ToUpperInvariant()) {
        Stop-WithError "checksum verification failed for $archiveName. The download may be corrupt or tampered with; the install stops here."
    }

    # --- unpack ------------------------------------------------------------
    $unpacked = Join-Path $tmp "unpacked"
    Expand-Archive -Path $archivePath -DestinationPath $unpacked -Force
    $exeSource = Join-Path $unpacked "agentop.exe"
    if (-not (Test-Path $exeSource)) {
        Stop-WithError "the archive did not contain agentop.exe. Please report it at https://github.com/$Repo/issues."
    }

    # --- choose the install directory ---------------------------------------
    $installDir = $env:AGENTOP_INSTALL_DIR
    if (-not $installDir) {
        $installDir = Join-Path $env:LOCALAPPDATA "agentop\bin"
    }
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    $installPath = Join-Path $installDir "agentop.exe"

    # Overwriting a running binary throws UnauthorizedAccessException, and the
    # raw message names nothing a person can act on. Name the process instead.
    if (Test-Path $installPath) {
        try {
            Remove-Item -Path $installPath -Force
        } catch {
            $running = Get-Process -Name "agentop" -ErrorAction SilentlyContinue |
                Where-Object { $_.Path -eq $installPath }
            if ($running) {
                Stop-WithError "agentop is already running (PID $(($running.Id) -join ', ')) and is holding $installPath open. Close it and run this again."
            }
            Stop-WithError "could not replace $($installPath): $($_.Exception.Message)"
        }
    }

    Copy-Item -Path $exeSource -Destination $installPath -Force

    # --- clear the mark of the web -------------------------------------------
    # The Windows half of what install.sh does with com.apple.quarantine.
    # Nothing here is code-signed, so a file carrying the zone identifier meets
    # a SmartScreen prompt on first run. Unblock-File is a no-op when the
    # stream is absent, which is the common case for a scripted download, so
    # that failure is expected and ignored.
    try {
        Unblock-File -Path $installPath -ErrorAction SilentlyContinue
    } catch {
    }

    Write-Info "agentop $version installed at $installPath"

    # --- PATH ---------------------------------------------------------------
    # Unlike install.sh, this writes PATH rather than printing it. No directory
    # is already on a Windows user's PATH, so a script that installs and then
    # prints an instruction has installed something nobody can run.
    if ($env:AGENTOP_NO_PATH) {
        Write-Info "AGENTOP_NO_PATH is set, so PATH was left alone. Add this directory yourself:"
        Write-Info "  $installDir"
    } else {
        Add-ToUserPath -Directory $installDir
    }

    Write-Info "try it: agentop --version"
} finally {
    Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
