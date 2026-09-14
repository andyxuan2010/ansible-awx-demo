#requires -Version 5.1
<#
.SYNOPSIS
    Discover IPv4/MAC information on a directly connected LAN and send Wake-on-LAN
    magic packets to every discovered MAC address.

.DESCRIPTION
    Designed to run locally on a Windows Domain Controller or other Windows server.

    Discovery sources:
      1. Active ICMP sweep to populate the local ARP/neighbor cache.
      2. Windows neighbor table (Get-NetNeighbor).
      3. Local Windows DHCP Server leases, when the DHCP Server PowerShell module
         is installed and the local computer is a DHCP server.

    IMPORTANT:
      - MAC addresses are Layer-2 information. A host on another routed subnet/VLAN
        normally cannot be discovered from ARP on this server.
      - Powered-off hosts usually cannot be rediscovered by ARP. DHCP lease data can
        preserve their MAC address, which is why this script also queries DHCP when
        available.
      - Wake-on-LAN must already be enabled in the target NIC/Windows/BIOS or UEFI.
      - Directed broadcasts are commonly blocked by routers. This script is intended
        primarily for the directly connected subnet specified by -Subnet.

.EXAMPLE
    .\Invoke-LanWakeAll.ps1 -Subnet 192.0.2.0/24

.EXAMPLE
    .\Invoke-LanWakeAll.ps1 -Subnet 192.0.2.0/24 -ResolveNames -Packets 5

.EXAMPLE
    .\Invoke-LanWakeAll.ps1 -Subnet 192.0.2.0/24 -DiscoverOnly

.EXAMPLE
    .\Invoke-LanWakeAll.ps1 -Subnet 192.0.2.0/24 -WhatIf
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [ValidatePattern('^\d{1,3}(\.\d{1,3}){3}/([0-9]|[12][0-9]|3[0-2])$')]
    [string]$Subnet,

    [Parameter(Mandatory = $false)]
    [ValidateRange(100, 5000)]
    [int]$PingTimeoutMs = 350,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 512)]
    [int]$Parallelism = 128,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 20)]
    [int]$Packets = 3,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 65535)]
    [int]$Port = 9,

    [Parameter(Mandatory = $false)]
    [switch]$ResolveNames,

    [Parameter(Mandatory = $false)]
    [switch]$DiscoverOnly,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 65534)]
    [int]$MaxHosts = 4096,

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory = 'C:\ProgramData\LanWake'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function ConvertTo-IPv4UInt32 {
    param([Parameter(Mandatory)][string]$Address)

    $bytes = [System.Net.IPAddress]::Parse($Address).GetAddressBytes()
    if ($bytes.Length -ne 4) {
        throw "IPv4 address required: $Address"
    }

    [array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

function ConvertFrom-IPv4UInt32 {
    param([Parameter(Mandatory)][uint32]$Value)

    $bytes = [BitConverter]::GetBytes($Value)
    [array]::Reverse($bytes)
    return ([System.Net.IPAddress]::new($bytes)).ToString()
}

function Get-SubnetInfo {
    param([Parameter(Mandatory)][string]$Cidr)

    $parts = $Cidr.Split('/')
    if ($parts.Count -ne 2) {
        throw "Invalid CIDR: $Cidr"
    }

    $ip = [System.Net.IPAddress]::Parse($parts[0])
    if ($ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw "Only IPv4 is supported: $Cidr"
    }

    $prefix = [int]$parts[1]
    if ($prefix -lt 0 -or $prefix -gt 32) {
        throw "Invalid IPv4 prefix length: $prefix"
    }

    $ipInt = ConvertTo-IPv4UInt32 $ip.IPAddressToString

    if ($prefix -eq 0) {
        [uint64]$mask64 = 0
    }
    else {
        [uint64]$mask64 = (([uint64][uint32]::MaxValue) -shl (32 - $prefix)) -band [uint64][uint32]::MaxValue
    }

    [uint32]$mask = $mask64
    [uint32]$network = $ipInt -band $mask
    [uint32]$hostMask = ([uint32]::MaxValue) -bxor $mask
    [uint32]$broadcast = $network -bor $hostMask

    [uint64]$addressCount = [uint64]1 -shl (32 - $prefix)
    [uint64]$usableHosts = if ($prefix -le 30) { $addressCount - 2 } else { $addressCount }

    [pscustomobject]@{
        InputCidr      = $Cidr
        PrefixLength   = $prefix
        NetworkUInt32  = $network
        BroadcastUInt32 = $broadcast
        NetworkAddress = ConvertFrom-IPv4UInt32 $network
        BroadcastAddress = ConvertFrom-IPv4UInt32 $broadcast
        AddressCount   = $addressCount
        UsableHosts    = $usableHosts
    }
}

function Test-IPv4InSubnet {
    param(
        [Parameter(Mandatory)][string]$Address,
        [Parameter(Mandatory)]$SubnetInfo
    )

    try {
        $value = ConvertTo-IPv4UInt32 $Address
        return ($value -ge $SubnetInfo.NetworkUInt32 -and
                $value -le $SubnetInfo.BroadcastUInt32)
    }
    catch {
        return $false
    }
}

function Normalize-MacAddress {
    param([AllowNull()][string]$Mac)

    if ([string]::IsNullOrWhiteSpace($Mac)) {
        return $null
    }

    $hex = ($Mac -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()

    # Standard Ethernet MAC = 6 octets / 12 hex characters.
    if ($hex.Length -ne 12) {
        return $null
    }

    if ($hex -eq '000000000000' -or $hex -eq 'FFFFFFFFFFFF') {
        return $null
    }

    $pairs = for ($i = 0; $i -lt 12; $i += 2) {
        $hex.Substring($i, 2)
    }

    return ($pairs -join ':')
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','OK')]
        [string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message
    Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8

    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'OK'    { Write-Host $line -ForegroundColor Green }
        default { Write-Host $line }
    }
}

function Invoke-PingSweep {
    param(
        [Parameter(Mandatory)][string[]]$Targets,
        [Parameter(Mandatory)][int]$TimeoutMs,
        [Parameter(Mandatory)][int]$BatchSize
    )

    $result = @{}

    for ($offset = 0; $offset -lt $Targets.Count; $offset += $BatchSize) {
        $last = [Math]::Min($offset + $BatchSize - 1, $Targets.Count - 1)
        $batch = @($Targets[$offset..$last])
        $pending = @()

        foreach ($target in $batch) {
            $ping = New-Object System.Net.NetworkInformation.Ping
            try {
                $task = $ping.SendPingAsync($target, $TimeoutMs)
                $pending += [pscustomobject]@{
                    IP   = $target
                    Ping = $ping
                    Task = $task
                }
            }
            catch {
                $ping.Dispose()
                $result[$target] = $false
            }
        }

        if ($pending.Count -gt 0) {
            try {
                $tasks = [System.Threading.Tasks.Task[]]@($pending | ForEach-Object { $_.Task })
                [System.Threading.Tasks.Task]::WaitAll($tasks)
            }
            catch {
                # Individual task results are inspected below.
            }

            foreach ($entry in $pending) {
                try {
                    $reply = $entry.Task.Result
                    $result[$entry.IP] =
                        ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success)
                }
                catch {
                    $result[$entry.IP] = $false
                }
                finally {
                    $entry.Ping.Dispose()
                }
            }
        }

        Write-Log ("Ping sweep progress: {0}/{1}" -f ($last + 1), $Targets.Count)
    }

    return $result
}

function Send-WolMagicPacket {
    param(
        [Parameter(Mandatory)][string]$Mac,
        [Parameter(Mandatory)][string]$BroadcastAddress,
        [Parameter(Mandatory)][int]$UdpPort,
        [Parameter(Mandatory)][int]$PacketCount
    )

    $normalized = Normalize-MacAddress $Mac
    if (-not $normalized) {
        throw "Invalid MAC address: $Mac"
    }

    $macBytes = @($normalized.Split(':') | ForEach-Object {
        [Convert]::ToByte($_, 16)
    })

    [byte[]]$packet = New-Object byte[] (6 + 16 * 6)

    for ($i = 0; $i -lt 6; $i++) {
        $packet[$i] = 0xFF
    }

    for ($repeat = 0; $repeat -lt 16; $repeat++) {
        [Array]::Copy(
            [byte[]]$macBytes,
            0,
            $packet,
            6 + ($repeat * 6),
            6
        )
    }

    $client = New-Object System.Net.Sockets.UdpClient
    try {
        $client.EnableBroadcast = $true
        $endpoint = New-Object System.Net.IPEndPoint(
            [System.Net.IPAddress]::Parse($BroadcastAddress),
            $UdpPort
        )

        for ($i = 1; $i -le $PacketCount; $i++) {
            [void]$client.Send($packet, $packet.Length, $endpoint)
            Start-Sleep -Milliseconds 100
        }
    }
    finally {
        $client.Close()
        $client.Dispose()
    }
}

# -----------------------------------------------------------------------------
# Initialization
# -----------------------------------------------------------------------------

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:LogPath = Join-Path $OutputDirectory "LanWake_$timestamp.log"
$CsvPath = Join-Path $OutputDirectory "LanWake_$timestamp.csv"
$JsonPath = Join-Path $OutputDirectory "LanWake_$timestamp.json"

Write-Log "LAN Wake discovery started on $env:COMPUTERNAME."
Write-Log "Running as $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)."

# Determine a subnet automatically when none was supplied.
if (-not $Subnet) {
    $cfg = Get-NetIPConfiguration |
        Where-Object {
            $_.IPv4DefaultGateway -and
            $_.NetAdapter.Status -eq 'Up'
        } |
        Select-Object -First 1

    if (-not $cfg) {
        throw 'Could not determine an active IPv4 interface with a default gateway. Specify -Subnet explicitly.'
    }

    $localAddress = $cfg.IPv4Address |
        Where-Object {
            $_.IPAddress -notlike '169.254.*'
        } |
        Select-Object -First 1

    if (-not $localAddress) {
        throw 'Could not determine an active IPv4 address. Specify -Subnet explicitly.'
    }

    $tempInfo = Get-SubnetInfo ("{0}/{1}" -f $localAddress.IPAddress, $localAddress.PrefixLength)
    $Subnet = "{0}/{1}" -f $tempInfo.NetworkAddress, $tempInfo.PrefixLength
}

$subnetInfo = Get-SubnetInfo $Subnet

if ($subnetInfo.PrefixLength -gt 30) {
    throw "Subnet $Subnet has no conventional broadcast host range. Use a prefix of /30 or larger LAN."
}

if ($subnetInfo.UsableHosts -gt $MaxHosts) {
    throw ("Subnet {0} contains {1} usable addresses, exceeding MaxHosts={2}. " +
           "Increase -MaxHosts deliberately if this is intended." -f
           $Subnet, $subnetInfo.UsableHosts, $MaxHosts)
}

Write-Log "Target subnet: $($subnetInfo.NetworkAddress)/$($subnetInfo.PrefixLength)"
Write-Log "Broadcast address: $($subnetInfo.BroadcastAddress)"
Write-Log "Usable IPv4 addresses to probe: $($subnetInfo.UsableHosts)"

# Find the directly connected interface for this subnet.
$localIpMatches = @(
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object {
            $_.IPAddress -ne '127.0.0.1' -and
            (Test-IPv4InSubnet -Address $_.IPAddress -SubnetInfo $subnetInfo)
        }
)

if ($localIpMatches.Count -eq 0) {
    throw ("No local NIC has an IPv4 address inside {0}. WOL broadcast is intended for a directly " +
           "connected subnet. Run the script on a host in that LAN." -f $Subnet)
}

$selectedLocalIp = $localIpMatches |
    Sort-Object SkipAsSource |
    Select-Object -First 1

$interfaceIndex = $selectedLocalIp.InterfaceIndex
$adapter = Get-NetAdapter -InterfaceIndex $interfaceIndex -ErrorAction Stop

Write-Log ("Using interface: {0} (Index {1}), local IP {2}, MAC {3}" -f
           $adapter.Name, $interfaceIndex, $selectedLocalIp.IPAddress, $adapter.MacAddress)

# Build host target list.
$targets = New-Object System.Collections.Generic.List[string]

for ([uint64]$value = [uint64]$subnetInfo.NetworkUInt32 + 1;
     $value -lt [uint64]$subnetInfo.BroadcastUInt32;
     $value++) {

    $targets.Add((ConvertFrom-IPv4UInt32 ([uint32]$value)))
}

# -----------------------------------------------------------------------------
# Active discovery
# -----------------------------------------------------------------------------

Write-Log "Starting active ping sweep. A reply is not required for ARP resolution on the local LAN."
$pingResults = Invoke-PingSweep `
    -Targets $targets.ToArray() `
    -TimeoutMs $PingTimeoutMs `
    -BatchSize $Parallelism

$pingReplies = @($pingResults.GetEnumerator() | Where-Object Value).Count
Write-Log "Ping sweep completed. ICMP replies: $pingReplies/$($targets.Count)."

# Give Windows a brief moment to finish neighbor-table updates.
Start-Sleep -Milliseconds 750

$rawRecords = New-Object System.Collections.Generic.List[object]

# -----------------------------------------------------------------------------
# Neighbor/ARP table
# -----------------------------------------------------------------------------

Write-Log "Reading the Windows IPv4 neighbor table."

$neighbors = @(
    Get-NetNeighbor `
        -AddressFamily IPv4 `
        -InterfaceIndex $interfaceIndex `
        -ErrorAction SilentlyContinue |
    Where-Object {
        (Test-IPv4InSubnet -Address $_.IPAddress -SubnetInfo $subnetInfo)
    }
)

foreach ($neighbor in $neighbors) {
    $mac = Normalize-MacAddress $neighbor.LinkLayerAddress

    if (-not $mac) {
        continue
    }

    $name = $null

    if ($ResolveNames) {
        try {
            $ptr = Resolve-DnsName -Name $neighbor.IPAddress -ErrorAction Stop |
                Where-Object { $_.Type -eq 'PTR' } |
                Select-Object -First 1

            if ($ptr) {
                $name = $ptr.NameHost.TrimEnd('.')
            }
        }
        catch {
            # DNS resolution is optional.
        }
    }

    $pinged = $false
    if ($pingResults.ContainsKey($neighbor.IPAddress)) {
        $pinged = [bool]$pingResults[$neighbor.IPAddress]
    }

    $rawRecords.Add([pscustomobject]@{
        Name          = $name
        IP            = $neighbor.IPAddress
        MAC           = $mac
        Source        = 'Neighbor'
        NeighborState = [string]$neighbor.State
        PingResponded = $pinged
        LeaseState    = $null
    })
}

Write-Log "Valid MAC addresses found in neighbor table: $($rawRecords.Count)."

# -----------------------------------------------------------------------------
# DHCP leases (optional)
# -----------------------------------------------------------------------------

$dhcpLeaseCount = 0

if (Get-Command Get-DhcpServerv4Lease -ErrorAction SilentlyContinue) {
    Write-Log "DHCP Server PowerShell module detected. Checking local DHCP leases."

    try {
        $scopes = @(Get-DhcpServerv4Scope -ComputerName $env:COMPUTERNAME -ErrorAction Stop)

        foreach ($scope in $scopes) {
            try {
                $leases = @(
                    Get-DhcpServerv4Lease `
                        -ComputerName $env:COMPUTERNAME `
                        -ScopeId $scope.ScopeId `
                        -AllLeases `
                        -ErrorAction Stop
                )

                foreach ($lease in $leases) {
                    $ip = [string]$lease.IPAddress

                    if (-not (Test-IPv4InSubnet -Address $ip -SubnetInfo $subnetInfo)) {
                        continue
                    }

                    $mac = Normalize-MacAddress ([string]$lease.ClientId)
                    if (-not $mac) {
                        continue
                    }

                    $pinged = $false
                    if ($pingResults.ContainsKey($ip)) {
                        $pinged = [bool]$pingResults[$ip]
                    }

                    $rawRecords.Add([pscustomobject]@{
                        Name          = [string]$lease.HostName
                        IP            = $ip
                        MAC           = $mac
                        Source        = 'DHCP'
                        NeighborState = $null
                        PingResponded = $pinged
                        LeaseState    = [string]$lease.AddressState
                    })

                    $dhcpLeaseCount++
                }
            }
            catch {
                Write-Log "Failed to read DHCP scope $($scope.ScopeId): $($_.Exception.Message)" 'WARN'
            }
        }

        Write-Log "Matching DHCP lease records with valid Ethernet MACs: $dhcpLeaseCount."
    }
    catch {
        Write-Log "DHCP Server module exists, but local DHCP leases could not be queried: $($_.Exception.Message)" 'WARN'
    }
}
else {
    Write-Log "DHCP Server PowerShell module not detected; DHCP lease discovery skipped." 'WARN'
}

# -----------------------------------------------------------------------------
# Deduplicate by MAC
# -----------------------------------------------------------------------------

$localMacs = @(
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        ForEach-Object { Normalize-MacAddress $_.MacAddress } |
        Where-Object { $_ }
)

$summary = New-Object System.Collections.Generic.List[object]

foreach ($group in ($rawRecords | Group-Object MAC | Sort-Object Name)) {
    $items = @($group.Group)

    # Prefer a current neighbor-table IP over a DHCP-only record.
    $best = $items |
        Sort-Object @{
            Expression = {
                if ($_.Source -eq 'Neighbor') { 0 } else { 1 }
            }
        }, @{
            Expression = {
                if ($_.PingResponded) { 0 } else { 1 }
            }
        } |
        Select-Object -First 1

    $names = @(
        $items.Name |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )

    $ips = @($items.IP | Sort-Object -Unique)
    $sources = @($items.Source | Sort-Object -Unique)
    $states = @(
        $items.NeighborState |
            Where-Object { $_ } |
            Sort-Object -Unique
    )
    $leaseStates = @(
        $items.LeaseState |
            Where-Object { $_ } |
            Sort-Object -Unique
    )

    $summary.Add([pscustomobject]@{
        Name             = ($names -join ',')
        IP               = $best.IP
        AllKnownIPs      = ($ips -join ',')
        MAC              = $group.Name
        Sources          = ($sources -join '+')
        PingResponded    = [bool](@($items | Where-Object PingResponded).Count -gt 0)
        NeighborState    = ($states -join ',')
        LeaseState       = ($leaseStates -join ',')
        IsLocalMachine   = ($localMacs -contains $group.Name)
        MagicPacketsSent = 0
        WakeResult       = if ($DiscoverOnly) { 'DiscoveryOnly' } else { 'Pending' }
        Error            = ''
    })
}

Write-Log "Unique MAC addresses after deduplication: $($summary.Count)."

# -----------------------------------------------------------------------------
# Send WOL packets
# -----------------------------------------------------------------------------

if (-not $DiscoverOnly) {
    foreach ($device in $summary) {
        if ($device.IsLocalMachine) {
            $device.WakeResult = 'SkippedLocalMachine'
            Write-Log "Skipping local adapter MAC $($device.MAC)." 'INFO'
            continue
        }

        $label = if ($device.Name) {
            "$($device.Name) [$($device.IP)]"
        }
        else {
            $device.IP
        }

        if ($PSCmdlet.ShouldProcess(
            "$label / $($device.MAC)",
            "Send $Packets Wake-on-LAN packet(s) to $($subnetInfo.BroadcastAddress):$Port"
        )) {
            try {
                Send-WolMagicPacket `
                    -Mac $device.MAC `
                    -BroadcastAddress $subnetInfo.BroadcastAddress `
                    -UdpPort $Port `
                    -PacketCount $Packets

                $device.MagicPacketsSent = $Packets
                $device.WakeResult = 'Sent'
                Write-Log "WOL sent: $label MAC=$($device.MAC), packets=$Packets." 'OK'
            }
            catch {
                $device.WakeResult = 'Failed'
                $device.Error = $_.Exception.Message
                Write-Log "WOL failed for $label MAC=$($device.MAC): $($_.Exception.Message)" 'ERROR'
            }
        }
        else {
            $device.WakeResult = 'WhatIf'
        }
    }
}

# -----------------------------------------------------------------------------
# Export and report
# -----------------------------------------------------------------------------

$summary |
    Sort-Object IP |
    Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8

$summary |
    Sort-Object IP |
    ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath $JsonPath -Encoding UTF8

$sentCount = @($summary | Where-Object WakeResult -eq 'Sent').Count
$failedCount = @($summary | Where-Object WakeResult -eq 'Failed').Count
$onlineCount = @($summary | Where-Object PingResponded).Count
$dhcpOnlyCount = @(
    $summary |
        Where-Object {
            $_.Sources -eq 'DHCP'
        }
).Count

Write-Log "----- SUMMARY -----"
Write-Log "Subnet: $($subnetInfo.NetworkAddress)/$($subnetInfo.PrefixLength)"
Write-Log "Unique MACs discovered: $($summary.Count)"
Write-Log "Devices replying to ICMP: $onlineCount"
Write-Log "DHCP-only MACs (useful for offline hosts): $dhcpOnlyCount"
Write-Log "WOL targets successfully sent: $sentCount"
Write-Log "WOL failures: $failedCount"
Write-Log "CSV report: $CsvPath"
Write-Log "JSON report: $JsonPath"
Write-Log "Log file: $script:LogPath"
Write-Log "LAN Wake operation completed." 'OK'

Write-Host ''
Write-Host 'Wake-on-LAN discovery summary:' -ForegroundColor Cyan
$summary |
    Sort-Object IP |
    Format-Table Name, IP, MAC, Sources, PingResponded, NeighborState, WakeResult -AutoSize

Write-Host ''
Write-Host "Log : $script:LogPath"
Write-Host "CSV : $CsvPath"
Write-Host "JSON: $JsonPath"
