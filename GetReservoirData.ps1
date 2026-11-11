<#
.SYNOPSIS
    Writes latest reservoir pool elevation and water temperature to a CSV for Max.

.DESCRIPTION
    Reads the latest values for the sites listed below from the USGS Water Data
    OGC API (api.waterdata.usgs.gov). This replaces the legacy
    waterservices.usgs.gov NWIS IV service, which USGS is retiring.

    Output columns (unchanged from the old script):
        LOCATION, POOL_ELEVATION, WATER_TEMPERATURE, UPDATE_TIME

    Behavior worth knowing:
      * All sites are fetched in ONE request (plus one for site names).
      * POOL_ELEVATION comes only from parameter 62614 (lake/reservoir
        elevation). A stream gage that reports only gage height (00065) shows
        N/A instead of a gage height presented as an elevation. A site can opt
        in to a different parameter with PoolParameter below.
      * A reading older than -MaxAgeHours is shown as N/A, not as a stale value.
      * If USGS cannot be reached, or no site returns any usable value, the
        existing CSV is left untouched and the script exits with code 1.
      * The CSV is written to a temp file and renamed, so Max never reads a
        half-written file.

    Works on Windows PowerShell 5.1 and PowerShell 7.

.PARAMETER OutputPath
    Where the CSV is written.

.PARAMETER LogPath
    Log file (appended). Set to "" to disable logging to a file.

.PARAMETER MaxAgeHours
    Readings older than this are treated as missing.

.PARAMETER Preview
    Print the rows to the console and do not write the CSV.
#>
[CmdletBinding()]
param(
    [string]$OutputPath  = "D:\WSI\DigitalMedia\Custom\ImportedData\reservoir_data.csv",
    [string]$LogPath     = "C:\ProgramData\WSI\Logs\GetReservoirData.log",
    [double]$MaxAgeHours = 12,
    [switch]$Preview
)

# ==============================================================================
# 1. CONFIGURATION - add or remove USGS sites here (order = row order in the CSV)
#
#   Id               USGS site number (no "USGS-" prefix)
#   Name             Optional. Text for the LOCATION column. Leave "" to use
#                    the name USGS publishes for the site.
#   PoolParameter    Optional. Defaults to 62614 (reservoir elevation). Set to
#                    "00065" only if you really want gage height in the
#                    POOL_ELEVATION column for a stream site.
#
#   Note: a site only fills POOL_ELEVATION if it reports the pool parameter.
#   Stream gages (e.g. Alum Creek at Africa, Big Darby) report temperature
#   and/or gage height only, so their POOL_ELEVATION is N/A.
# ==============================================================================
$Sites = @(
    @{ Id = "03220500";         Name = "" },   # O'Shaughnessy Reservoir
    @{ Id = "03220510";         Name = "" },   # Scioto R. at O'Shaughnessy Dam
    @{ Id = "03228805";         Name = "" },   # Alum Creek at Africa (stream gage)
    @{ Id = "03228400";         Name = "" },   # Hoover Reservoir
    @{ Id = "395540082291600";  Name = "" },   # Buckeye Lake
    @{ Id = "03260500";         Name = "" },   # Indian Lake
    @{ Id = "03141000";         Name = "" },   # Senecaville Lake
    @{ Id = "03140950";         Name = "" },   # Beaver Creek above Senecaville Lake
    @{ Id = "395339083130100";  Name = "" }    # Big Darby Creek above Georgesville
)

$ApiBase       = "https://api.waterdata.usgs.gov/ogcapi/v1/collections"
$TempParameter = "00010"      # water temperature, degrees C
$DefaultPool   = "62614"      # lake/reservoir water surface elevation, ft
$Attempts      = 3
$TimeoutSec    = 30

# ==============================================================================
# 2. HELPERS
# ==============================================================================
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Write-Log([string]$Message, [string]$Level = "INFO") {
    $line = "{0} [{1}] {2}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $Level, $Message
    if ($Level -eq "ERROR")     { Write-Host $line -ForegroundColor Red }
    elseif ($Level -eq "WARN")  { Write-Host $line -ForegroundColor Yellow }
    else                        { Write-Host $line }
    if (-not $LogPath) { return }
    try {
        $dir = Split-Path -Path $LogPath -Parent
        if ($dir -and -not (Test-Path -Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        # Keep the log from growing forever: start fresh past ~1 MB.
        if ((Test-Path -Path $LogPath) -and ((Get-Item -Path $LogPath).Length -gt 1MB)) { Remove-Item -Path $LogPath -Force }
        Add-Content -Path $LogPath -Value $line
    }
    catch { }   # never let logging break the data run
}

function Invoke-ApiGet([string]$Url) {
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            return Invoke-RestMethod -Uri $Url -Method Get -TimeoutSec $TimeoutSec
        }
        catch {
            if ($i -eq $Attempts) { throw }
            Write-Log "Request failed (attempt $i of $Attempts): $($_.Exception.Message). Retrying." "WARN"
            Start-Sleep -Seconds (2 * $i)
        }
    }
}

# Handles both a string (Windows PowerShell 5.1) and an already-parsed DateTime (PowerShell 7).
function ConvertTo-Instant($Value) {
    if ($Value -is [datetime]) { return [DateTimeOffset]$Value }
    return [DateTimeOffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None)
}

# ==============================================================================
# 3. FETCH
# ==============================================================================
$siteIds    = @($Sites | ForEach-Object { "USGS-" + $_.Id })
$poolParams = @($Sites | ForEach-Object { if ($_.PoolParameter) { $_.PoolParameter } else { $DefaultPool } })
$paramList  = @($TempParameter) + $poolParams | Select-Object -Unique

$idList    = $siteIds -join ","
$valuesUrl = "$ApiBase/latest-continuous/items?monitoring_location_id=$idList&parameter_code=$($paramList -join ',')&f=json&limit=1000"
$namesUrl  = "$ApiBase/monitoring-locations/items?id=$idList&properties=monitoring_location_name&f=json&limit=1000"

Write-Log "Fetching latest values for $($Sites.Count) sites."
try {
    $valuesResponse = Invoke-ApiGet $valuesUrl
}
catch {
    Write-Log "USGS request failed; leaving the existing CSV in place. $($_.Exception.Message)" "ERROR"
    exit 1
}

# Names are nice to have; a failure here only affects the LOCATION text.
$usgsNames = @{}
try {
    $namesResponse = Invoke-ApiGet $namesUrl
    foreach ($f in $namesResponse.features) { $usgsNames[[string]$f.id] = [string]$f.properties.monitoring_location_name }
}
catch {
    Write-Log "Could not fetch site names; using configured names or site numbers. $($_.Exception.Message)" "WARN"
}

# Newest reading per site + parameter (a site can have more than one series for a parameter).
$latest = @{}
foreach ($f in $valuesResponse.features) {
    $p = $f.properties
    if ($null -eq $p.value -or "$($p.value)" -eq "") { continue }
    $key = "$($p.monitoring_location_id)|$($p.parameter_code)"
    $when = ConvertTo-Instant $p.time
    if (-not $latest.ContainsKey($key) -or $when -gt $latest[$key].When) {
        $latest[$key] = @{
            When  = $when
            Value = [double]::Parse([string]$p.value, [Globalization.CultureInfo]::InvariantCulture)
        }
    }
}

# ==============================================================================
# 4. BUILD ROWS
# ==============================================================================
$now = [DateTimeOffset]::UtcNow
$usable = 0

function Get-Reading([string]$SiteId, [string]$Parameter) {
    $key = "USGS-$SiteId|$Parameter"
    if (-not $latest.ContainsKey($key)) { return $null }
    $r = $latest[$key]
    if (($now - $r.When).TotalHours -gt $MaxAgeHours) {
        Write-Log "Site $SiteId parameter ${Parameter}: reading from $($r.When.ToString('u')) is older than $MaxAgeHours h; treating as missing." "WARN"
        return $null
    }
    return $r
}

$rows = foreach ($site in $Sites) {
    $id = [string]$site.Id
    $poolParam = if ($site.PoolParameter) { [string]$site.PoolParameter } else { $DefaultPool }

    $name = if ($site.Name) { [string]$site.Name }
            elseif ($usgsNames.ContainsKey("USGS-$id")) { $usgsNames["USGS-$id"] }
            else { "USGS $id" }

    $pool = "N/A"; $tempF = "N/A"; $update = "N/A"
    $times = @()

    $poolReading = Get-Reading $id $poolParam
    if ($poolReading) {
        $pool = [math]::Round($poolReading.Value, 2)
        $times += $poolReading.When
    }

    $tempReading = Get-Reading $id $TempParameter
    if ($tempReading) {
        $tempF = [math]::Round(($tempReading.Value * 9 / 5) + 32, 0)
        $times += $tempReading.When
    }

    if ($times.Count -gt 0) {
        $newest = ($times | Sort-Object -Descending | Select-Object -First 1)
        $update = $newest.ToLocalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffzzz")
        $usable++
    }
    else {
        Write-Log "Site $id ($name): no usable readings." "WARN"
    }

    [PSCustomObject]@{
        LOCATION          = $name
        POOL_ELEVATION    = $pool
        WATER_TEMPERATURE = $tempF
        UPDATE_TIME       = $update
    }
}

# ==============================================================================
# 5. WRITE (atomically) - or preview
# ==============================================================================
if ($usable -eq 0) {
    Write-Log "No site returned a usable reading; leaving the existing CSV in place." "ERROR"
    exit 1
}

if ($Preview) {
    $rows | Format-Table -AutoSize
    Write-Log "Preview only; nothing written. $usable of $($Sites.Count) sites had data."
    exit 0
}

try {
    $dir = Split-Path -Path $OutputPath -Parent
    if ($dir -and -not (Test-Path -Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tmp = "$OutputPath.tmp"
    $rows | Export-Csv -Path $tmp -NoTypeInformation -Encoding ASCII
    Move-Item -Path $tmp -Destination $OutputPath -Force
}
catch {
    Write-Log "Could not write $OutputPath : $($_.Exception.Message)" "ERROR"
    exit 1
}

Write-Log "Wrote $OutputPath ($usable of $($Sites.Count) sites had data)."
exit 0
