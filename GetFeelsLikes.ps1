# Target coordinates updated for Columbus, OH
$Lat = "39.9612"
$Lon = "-82.9988"
$OutputFile = "D:\WSI\DigitalMedia\Custom\ImportedData\ndfd_feelslikes.csv"

# Get today's local date at midnight to filter out past days
$Today = (Get-Date).Date

# NWS API requires a User-Agent header
$Headers = @{
    "User-Agent" = "(WBNS, wx@10tv.com)"
}

# Ensure destination directory exists
$TargetDir = Split-Path -Path $OutputFile -Parent
if (-not (Test-Path -Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
}

Write-Host "Fetching NWS Grid Metadata for Columbus..." -ForegroundColor Cyan
$PointsUrl = "https://api.weather.gov/points/$Lat,$Lon"
$GridMetadata = Invoke-RestMethod -Uri $PointsUrl -Headers $Headers
$GridDataUrl = $GridMetadata.properties.forecastGridData

Write-Host "Fetching Forecast Grid Data..." -ForegroundColor Cyan
$GridData = Invoke-RestMethod -Uri $GridDataUrl -Headers $Headers
$ApparentTempValues = $GridData.properties.apparentTemperature.values

if ($null -eq $ApparentTempValues) {
    Write-Host "No apparent temperature data found." -ForegroundColor Red
    exit
}

# Initialize master tracking dictionary
$DailyMetrics = @{}

foreach ($Item in $ApparentTempValues) {
    $UtcTimeStr = $Item.validTime.Split("/")[0]
    $LocalDateTime = [DateTime]::Parse($UtcTimeStr).ToLocalTime()
    
    # CRITICAL FILTER: Skip data points from yesterday
    if ($LocalDateTime.Date -lt $Today) { continue }

    $DateKey = $LocalDateTime.ToString("yyyy-MM-dd")
    $Hour = $LocalDateTime.Hour

    $Celsius = $Item.value
    if ($null -eq $Celsius) { continue }

    # Convert to Fahrenheit and round to nearest whole degree
    $Fahrenheit = [Math]::Round(($Celsius * 9 / 5) + 32, 0)

    if (-not $DailyMetrics.ContainsKey($DateKey)) {
        $DailyMetrics[$DateKey] = @{
            MaxHeatIndex        = $null
            MinWindChill        = $null
            MinWindChillDaytime = $null
        }
    }

    # 1. Parse Heat Index (>= 80°F)
    if ($Fahrenheit -ge 80) {
        if ($null -eq $DailyMetrics[$DateKey].MaxHeatIndex -or $Fahrenheit -gt $DailyMetrics[$DateKey].MaxHeatIndex) {
            $DailyMetrics[$DateKey].MaxHeatIndex = $Fahrenheit
        }
    }

    # 2. Parse Wind Chill (<= 50°F)
    if ($Fahrenheit -le 50) {
        if ($null -eq $DailyMetrics[$DateKey].MinWindChill -or $Fahrenheit -lt $DailyMetrics[$DateKey].MinWindChill) {
            $DailyMetrics[$DateKey].MinWindChill = $Fahrenheit
        }

        # Daytime Window (7:00 AM to 5:00 PM local time inclusive)
        if ($Hour -ge 7 -and $Hour -le 17) {
            if ($null -eq $DailyMetrics[$DateKey].MinWindChillDaytime -or $Fahrenheit -lt $DailyMetrics[$DateKey].MinWindChillDaytime) {
                $DailyMetrics[$DateKey].MinWindChillDaytime = $Fahrenheit
            }
        }
    }
}

# Construct structured objects for CSV export
$CsvData = foreach ($Date in ($DailyMetrics.Keys | Sort-Object)) {
    $DayOfWeek = [DateTime]::Parse($Date).ToString("ddd").ToUpper()

    [PSCustomObject]@{
        Day                 = $DayOfWeek
        MaxHeatIndex        = $DailyMetrics[$Date].MaxHeatIndex
        MinWindChill        = $DailyMetrics[$Date].MinWindChill
        MinWindChillDaytime = $DailyMetrics[$Date].MinWindChillDaytime
    }
}

# Export cleanly to CSV matching precise column order
$CsvData | Select-Object Day, MaxHeatIndex, MinWindChill, MinWindChillDaytime | Export-Csv -Path $OutputFile -NoTypeInformation

Write-Host "Success! Cleaned data exported to $OutputFile" -ForegroundColor Green