# 1. Configuration - Add or remove USGS Station IDs here
$stations = @(
    "03220500", # O'Shaughnessy Reservoir
    "03220510", # O'Shaughnessy Dam
    "03228805", # Alum Creek Lake
    "03228400", # Hoover Reservoir
    "395540082291600", # Buckeye Lake
    "03260500", # Indian Lake
    "03141000", # Senecaville Lake
    "03140950", # Beaver Creek above Senecaville Lake
    "395339083130100" # Big Darby Creek above Georgesville
)

# USGS Parameter Codes: 00010 (Temp), 62614 (Pool Level), 00065 (Gage Height)
$pCodes = "00010,62614,00065"

# --- FILEPATH ---
$csvPath = "D:\WSI\DigitalMedia\Custom\ImportedData\reservoir_data.csv"

$results = foreach ($id in $stations) {
    # Initialize variables for this specific station
    $locName    = "Unknown ($id)"
    $tempF      = "N/A"
    $pool       = "N/A"
    $updateTime = "N/A"

    try {
        # Fetch data via Legacy IV (Instantaneous Values) Service
        $url = "https://waterservices.usgs.gov/nwis/iv/?format=json&sites=$id&parameterCd=$pCodes&siteStatus=all"
        $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop

        if ($response.value.timeSeries.Count -gt 0) {
            # Grab the location name from the first available timeseries
            $locName = $response.value.timeSeries[0].sourceInfo.siteName

            foreach ($ts in $response.value.timeSeries) {
                $latestData = $ts.values[0].value | Select-Object -Last 1
                if ($latestData) {
                    $val = [double]$latestData.value
                    $updateTime = $latestData.dateTime
                    $pCode = $ts.variable.variableCode[0].value

                    if ($pCode -eq "00010") {
                        # Rounded to 0 decimal places for nearest full degree
                        $tempF = [math]::Round(($val * 9/5) + 32, 0)
                    }
                    elseif ($pCode -eq "62614" -or $pCode -eq "00065") {
                        # Keeping pool levels at 2 decimal places for accuracy
                        $pool = [math]::Round($val, 2)
                    }
                }
            }
        }
    }
    catch {
        Write-Host "Note: Skipping station $id (No response)" -ForegroundColor Gray
    }

    # Create the object for the CSV row
    [PSCustomObject]@{
        LOCATION          = $locName
        POOL_ELEVATION    = $pool
        WATER_TEMPERATURE = $tempF
        UPDATE_TIME       = $updateTime
    }
}

# 2. Export (Overwrites file)
if ($results) {
    $results | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "Success! Data saved to $csvPath" -ForegroundColor Green
}