<#
.SYNOPSIS
    Downloads and silently installs Tailscale on Windows, then registers the host.

.DESCRIPTION
    Finds the current stable amd64 Tailscale MSI, installs it without launching
    the client, registers the host in unattended mode, and reports its status.

.PARAMETER AuthKey
    Tailscale auth key. If omitted, TS_AUTH_KEY is read from the environment.

.PARAMETER LogPath
    Transcript log path. Defaults to install-tailscale.log beside this script.

.EXAMPLE
    $env:TS_AUTH_KEY = 'tskey-auth-YOUR_KEY'
    .\install-tailscale.ps1

    Uses TS_AUTH_KEY from the current PowerShell session and writes the log
    beside the script.

.EXAMPLE
    .\install-tailscale.ps1 -AuthKey 'tskey-auth-YOUR_KEY'

    Supplies the auth key as a script parameter.

.EXAMPLE
    .\install-tailscale.ps1 -AuthKey 'tskey-auth-YOUR_KEY' -LogPath 'C:\Logs\tailscale-install.log'

    Supplies the auth key as a parameter and writes the transcript to a custom path.

.NOTES
    Version: 1.3.0

.CHANGELOG
    1.3.0 - Added administrator, download, signature, retry, and cleanup validation.
    1.2.0 - Added transcript logging and the -LogPath parameter.
    1.1.0 - Added the -AuthKey parameter and MSI exit-code validation.
    1.0.0 - Initial stable amd64 silent-install and unattended-registration script.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AuthKey,

    [Parameter(Mandatory = $false)]
    [string]$LogPath
)

$ErrorActionPreference = 'Stop'

$stableUrl = 'https://pkgs.tailscale.com/stable/'
$downloadTimeoutSeconds = 60
$downloadAttempts = 3
$tailscaleExe = $null
$msiFile = $null
$transcriptStarted = $false

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Download {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$OutFile
    )

    for ($attempt = 1; $attempt -le $downloadAttempts; $attempt++) {
        try {
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing `
                -TimeoutSec $downloadTimeoutSeconds -ErrorAction Stop
            return
        }
        catch {
            if ($attempt -eq $downloadAttempts) {
                throw
            }

            Write-Warning "Download failed on attempt $attempt of $downloadAttempts. Retrying."
            Start-Sleep -Seconds ([Math]::Min(5 * $attempt, 15))
        }
    }
}

if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $LogPath = Join-Path $PSScriptRoot 'install-tailscale.log'
}

$logDirectory = Split-Path -Path $LogPath -Parent
if (-not [string]::IsNullOrWhiteSpace($logDirectory) -and
    -not (Test-Path -LiteralPath $logDirectory)) {
    New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
}

Start-Transcript -Path $LogPath -Append | Out-Null
$transcriptStarted = $true

try {
    if (-not (Test-IsAdministrator)) {
        throw 'This script must be run from an elevated PowerShell session.'
    }

    if ([string]::IsNullOrWhiteSpace(${env:ProgramFiles})) {
        throw 'The ProgramFiles environment variable is not available.'
    }
    $tailscaleExe = Join-Path ${env:ProgramFiles} 'Tailscale\tailscale.exe'

    # Prefer -AuthKey when provided; otherwise use TS_AUTH_KEY from the environment.
    $effectiveAuthKey = $AuthKey
    if ([string]::IsNullOrWhiteSpace($effectiveAuthKey)) {
        $effectiveAuthKey = $env:TS_AUTH_KEY
    }
    if ($null -ne $effectiveAuthKey) {
        $effectiveAuthKey = $effectiveAuthKey.Trim()
    }

    if ([string]::IsNullOrWhiteSpace($effectiveAuthKey) -or
        $effectiveAuthKey -eq 'tskey-auth-REPLACE_WITH_YOUR_KEY') {
        throw 'Set TS_AUTH_KEY or provide -AuthKey with a valid Tailscale auth key before running this script.'
    }
    $env:TS_AUTH_KEY = $effectiveAuthKey

    Write-Output "Starting Tailscale installation. Log: $LogPath"
    $page = Invoke-WebRequest -Uri $stableUrl -UseBasicParsing `
        -TimeoutSec $downloadTimeoutSeconds -ErrorAction Stop
    $msiPattern = 'tailscale-setup-(?<Version>[0-9]+(?:\.[0-9]+)*)-amd64\.msi'
    $msiMatches = [regex]::Matches(
        $page.Content,
        $msiPattern,
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if ($msiMatches.Count -eq 0) {
        throw "Could not find the current amd64 Tailscale installer on $stableUrl"
    }

    $msiName = $msiMatches |
        ForEach-Object { $_.Value } |
        Sort-Object -Unique |
        Sort-Object { [version]([regex]::Match($_, $msiPattern).Groups['Version'].Value) } -Descending |
        Select-Object -First 1

    $msiUrl = "$stableUrl$msiName"
    if ([string]::IsNullOrWhiteSpace($env:TEMP)) {
        throw 'The TEMP environment variable is not available.'
    }
    $msiFile = Join-Path $env:TEMP "tailscale-setup-$([guid]::NewGuid().ToString('N')).msi"
    Write-Output "Downloading $msiName"
    Invoke-Download -Uri $msiUrl -OutFile $msiFile

    if (-not (Test-Path -LiteralPath $msiFile -PathType Leaf)) {
        throw "The Tailscale installer was not downloaded to $msiFile"
    }

    $signature = Get-AuthenticodeSignature -FilePath $msiFile
    if ($signature.Status -ne 'Valid') {
        throw "The downloaded Tailscale installer signature is not valid (status: $($signature.Status))."
    }

    Write-Output 'Installing Tailscale silently'
    $msiexecPath = (Get-Command msiexec.exe -ErrorAction Stop).Path
    $installProcess = Start-Process -FilePath $msiexecPath -Wait -NoNewWindow -PassThru -ArgumentList @(
        '/i',
        "`"$msiFile`"",
        '/qn',
        '/norestart',
        'TS_NOLAUNCH=1',
        'TS_UNATTENDEDMODE=always'
    )
    if ($installProcess.ExitCode -notin @(0, 3010)) {
        throw "Tailscale MSI installation failed with exit code $($installProcess.ExitCode)."
    }
    if ($installProcess.ExitCode -eq 3010) {
        Write-Warning 'Tailscale installed successfully, but Windows reported that a restart may be required.'
    }

    if (-not (Test-Path -LiteralPath $tailscaleExe)) {
        throw "Tailscale was installed, but $tailscaleExe was not found."
    }

    Write-Output 'Registering this host with Tailscale'
    & $tailscaleExe up "--auth-key=$env:TS_AUTH_KEY" '--unattended=true'
    if ($LASTEXITCODE -ne 0) {
        throw "Tailscale registration failed with exit code $LASTEXITCODE."
    }

    & $tailscaleExe status
    if ($LASTEXITCODE -ne 0) {
        throw "Tailscale status failed with exit code $LASTEXITCODE."
    }

    Write-Output 'Tailscale installation and registration completed successfully.'
}
catch {
    Write-Output "Tailscale installation failed: $($_.Exception.Message)"
    throw
}
finally {
    Remove-Item Env:TS_AUTH_KEY -ErrorAction SilentlyContinue
    if ($msiFile -and (Test-Path -LiteralPath $msiFile)) {
        Remove-Item -LiteralPath $msiFile -Force -ErrorAction SilentlyContinue
    }
    if ($transcriptStarted) {
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    }
}
