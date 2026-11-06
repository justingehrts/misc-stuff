# ==============================================================================
# 1. GRAPHIC CANVAS & FILE PATH CONFIGURATION
# ==============================================================================
$CONFIG_FILE_PATH = "C:\LOCAL\Scripts\GetRiverData-Config.txt"
$OUTPUT_CSV_PATH  = "D:\WSI\DigitalMedia\Custom\ImportedData\MaxHydrographData.csv"

$CANVAS_HEIGHT_PX = 700  # Total vertical pixel size of your Max canvas

# Timeline step parameters: 3 days past (72h) to 5 days future (120h)
$HISTORY_HOURS  = 72
$FORECAST_HOURS = 120
$STEP_HOURS     = 6

# ==============================================================================
# 2. HELPER FUNCTIONS
# ==============================================================================
function Get-StageCategory($value, $thresholds) {
    if ($value -eq -9999 -or $null -eq $value) { return "N/A" }
    if ($thresholds.major -ne -9999 -and $value -ge $thresholds.major) { return "Major" }
    if ($thresholds.moderate -ne -9999 -and $value -ge $thresholds.moderate) { return "Moderate" }
    if ($thresholds.minor -ne -9999 -and $value -ge $thresholds.minor) { return "Minor" }
    if ($thresholds.action -ne -9999 -and $value -ge $thresholds.action) { return "Action" }
    return "No Flooding"
}

function Get-RelevantImpactText($max_val, $raw_impacts) {
    if ($max_val -eq -9999 -or $null -eq $raw_impacts) { return "No specific threshold impacts expected." }
    
    $highest_impact_text = "No severe impact thresholds crossed."
    $highest_impact_stage = -9999

    foreach ($impact in $raw_impacts) {
        $stage_trigger = $impact.stage
        $impact_statement = $impact.text

        if ($null -ne $stage_trigger) {
            if ($max_val -ge $stage_trigger -and $stage_trigger -gt $highest_impact_stage) {
                $highest_impact_stage = $stage_trigger
                $highest_impact_text = "At $stage_trigger ft: $impact_statement".Trim()
            }
        }
    }
    return $highest_impact_text
}

# ==============================================================================
# 3. CORE PROCESSING ENGINE FOR A SINGLE STATION
# ==============================================================================
function Get-RiverRow($station_id, $config_name) {
    $meta_url = "https://api.water.noaa.gov/nwps/v1/gauges/$station_id"
    $timeline_url = "https://api.water.noaa.gov/nwps/v1/gauges/$station_id/stageflow"

    try {
        # Force TLS 1.2/1.3 for security handshakes with NOAA
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $meta_res = Invoke-RestMethod -Uri $meta_url -Method Get -TimeoutSec 15
        $time_res = Invoke-RestMethod -Uri $timeline_url -Method Get -TimeoutSec 15
    }
    catch {
        Write-Warning "Connection failed for ${station_id}: $_"
        return $null
    }

    # Extract flood thresholds
    $categories = $meta_res.flood.categories
    $thresholds = @{
        action   = if ($categories.action.stage)   { $categories.action.stage }   else { -9999 }
        minor    = if ($categories.minor.stage)    { $categories.minor.stage }    else { -9999 }
        moderate = if ($categories.moderate.stage) { $categories.moderate.stage } else { -9999 }
        major    = if ($categories.major.stage)    { $categories.major.stage }    else { -9999 }
    }
    $raw_impacts = $meta_res.flood.impacts

    # Combine timeline data points into a unified list
    $raw_points = [System.Collections.Generic.List[PSObject]]::new()
    $forecast_values = [System.Collections.Generic.List[double]]::new()

    foreach ($obs in $time_res.observed.data) {
        if ($null -ne $obs.primary) {
            $parsed_time = [DateTime]::Parse($obs.validTime).ToLocalTime()
            $raw_points.Add([PSCustomObject]@{ DateTime = $parsed_time; Stage = [double]$obs.primary })
        }
    }
    foreach ($fcst in $time_res.forecast.data) {
        if ($null -ne $fcst.primary) {
            $parsed_time = [DateTime]::Parse($fcst.validTime).ToLocalTime()
            $raw_points.Add([PSCustomObject]@{ DateTime = $parsed_time; Stage = [double]$fcst.primary })
            $forecast_values.Add([double]$fcst.primary)
        }
    }

    if ($raw_points.Count -eq 0) {
        Write-Warning "No active reporting timeline for ${station_id}."
        return $null
    }

    # Generate the rigid 6-hour timeline intervals relative to "Now"
    $now = (Get-Date).AddMinutes(-((Get-Date).Minute)).AddSeconds(-((Get-Date).Second)) # Round to nearest hour
    $target_timeline = @()
    for ($i = -$HISTORY_HOURS; $i -le $FORECAST_HOURS; $i += $STEP_HOURS) {
        $target_timeline += $now.AddHours($i)
    }

    # ==============================================================================
    # REINDEXING & TRUE LINEAR TIME-INTERPOLATION ENGINE
    # ==============================================================================
    $sorted_points = $raw_points | Sort-Object DateTime
    $grid_stages = @{}

    foreach ($ts in $target_timeline) {
        # 1. Check if an exact time match exists in the raw data
        $exact_match = $sorted_points | Where-Object { $_.DateTime -eq $ts }
        if ($null -ne $exact_match) {
            $grid_stages[$ts] = $exact_match[0].Stage
            continue
        }

        # 2. Find the bounding points (closest before and closest after the target time)
        $point_before = $sorted_points | Where-Object { $_.DateTime -lt $ts } | Sort-Object DateTime -Descending | Select-Object -First 1
        $point_after  = $sorted_points | Where-Object { $_.DateTime -gt $ts } | Sort-Object DateTime | Select-Object -First 1

        # 3. Apply linear interpolation math based on time distance
        if ($null -ne $point_before -and $null -ne $point_after) {
            $t1 = $point_before.DateTime.Ticks
            $t2 = $point_after.DateTime.Ticks
            $target_t = $ts.Ticks

            $s1 = $point_before.Stage
            $s2 = $point_after.Stage

            $interpolated_stage = $s1 + ($s2 - $s1) * (($target_t - $t1) / ($t2 - $t1))
            $grid_stages[$ts] = $interpolated_stage
        }
        elseif ($null -ne $point_before) { $grid_stages[$ts] = $point_before.Stage }
        elseif ($null -ne $point_after)  { $grid_stages[$ts] = $point_after.Stage }
        else { $grid_stages[$ts] = $canvas_floor }
    }

    # Extract text metadata labels
    $current_val = $grid_stages[$now]
    $max_fcst_val = if ($forecast_values.Count -gt 0) { ($forecast_values | Measure-Object -Maximum).Maximum } else { -9999 }
    $max_fcst_val = [Math]::Round($max_fcst_val, 2)

    $current_stage_text = Get-StageCategory $current_val $thresholds
    $max_fcst_stage_text = Get-StageCategory $max_fcst_val $thresholds
    $upcoming_impact_string = Get-RelevantImpactText $max_fcst_val $raw_impacts

    # Dynamic viewport calculation (Zoom window calibration)
    $math_pool = [System.Collections.Generic.List[double]]::new()
    foreach ($ts in $target_timeline) { $math_pool.Add($grid_stages[$ts]) }
    foreach ($v in $thresholds.Values) { if ($v -ne -9999 -and $v -le ($max_fcst_val + 3)) { $math_pool.Add($v) } }

    $min_data = ($math_pool | Measure-Object -Minimum).Minimum
    $max_data = ($math_pool | Measure-Object -Maximum).Maximum

    $canvas_floor = [Math]::Max(0.0, [Math]::Round($min_data - 2.0, 1))
    $canvas_ceiling = [Math]::Round($max_data + 2.0, 1)
    $scale_range = $canvas_ceiling - $canvas_floor
    if ($scale_range -le 0) { $scale_range = 1.0 }

    # Math conversion lambdas
    $ToScalePercentage = {
        param($val)
        if ($val -eq -9999 -or $null -eq $val) { return 0.0 }
        if ($val -gt $canvas_ceiling) { return 0.0 }
        $pct = (($val - $canvas_floor) / $scale_range) * 100.0
        return [Math]::Round([Math]::Max(0.0, [Math]::Min(100.0, $pct)), 2)
    }

    $ToPixelY = {
        param($val)
        if ($val -eq -9999 -or $null -eq $val) { return 0 }
        $pct = ($val - $canvas_floor) / $scale_range
        $pixel_pos = $pct * $CANVAS_HEIGHT_PX
        return [int][Math]::Max(0, [Math]::Min($CANVAS_HEIGHT_PX, $pixel_pos))
    }

    $ToLabelPixelY = {
        param($val)
        if ($val -eq -9999 -or $null -eq $val -or $val -gt $canvas_ceiling) { return -9999 }
        $pct = ($val - $canvas_floor) / $scale_range
        return [int]($pct * $CANVAS_HEIGHT_PX)
    }

    # Construct base output record row object
    $output_row = [ordered]@{
        LocationID               = $station_id
        LocationName             = if ($config_name) { $config_name } else { $meta_res.name }
        CanvasFloorFt            = $canvas_floor
        CanvasCeilingFt          = $canvas_ceiling
        ActionStageLevel         = $thresholds.action
        MinorFloodLevel          = $thresholds.minor
        ModerateFloodLevel       = $thresholds.moderate
        MajorFloodLevel          = $thresholds.major
        CurrentStageDesc         = $current_stage_text
        MaxForecastStageDesc     = $max_fcst_stage_text
        MaxForecastValue         = $max_fcst_val
        UpcomingImpactText       = $upcoming_impact_string
        
        Action_Box_ScaleHeight   = &$ToScalePercentage $thresholds.action
        Minor_Box_ScaleHeight    = &$ToScalePercentage $thresholds.minor
        Moderate_Box_ScaleHeight = &$ToScalePercentage $thresholds.moderate
        Major_Box_ScaleHeight    = &$ToScalePercentage $thresholds.major

        Action_Label_Y           = &$ToLabelPixelY $thresholds.action
        Minor_Label_Y            = &$ToLabelPixelY $thresholds.minor
        Moderate_Label_Y         = &$ToLabelPixelY $thresholds.moderate
        Major_Label_Y            = &$ToLabelPixelY $thresholds.major
    }

    # Generate matrix time-grid pairs natively
    foreach ($ts in $target_timeline) {
        $hours_diff = [int](($ts - $now).TotalHours)
        $stage_ft = $grid_stages[$ts]
        
        $time_label = $ts.ToString("ddd h tt").ToUpper()
        $time_label = $time_label -replace '\s+', ' '

        if ($hours_diff -lt 0) { $prefix = "Obs_Minus_$( [Math]::Abs($hours_diff) )h" }
        elseif ($hours_diff -eq 0) { $prefix = "Current_Obs" }
        else { $prefix = "Fcst_Plus_$( $hours_diff )h" }
            
        $output_row["${prefix}_Y"] = &$ToPixelY $stage_ft
        $output_row["${prefix}_Time"] = $time_label
    }

    return [PSCustomObject]$output_row
}

# ==============================================================================
# 4. CONFIG FILE PARSER AND SYSTEM EXECUTIVE LOOP
# ==============================================================================
Write-Host "Opening config file: $CONFIG_FILE_PATH"
if (Test-Path $CONFIG_FILE_PATH) {
    $all_station_rows = @()
    $lines = Get-Content $CONFIG_FILE_PATH

    foreach ($line in $lines) {
        $line = $line.Trim()
        if (-not $line -or $line.StartsWith("#")) { continue }

        $parts = $line.Split(",")
        $station_id = $parts[0].Trim()
        $config_name = if ($parts.Length -gt 1) { $parts[1].Trim() } else { "" }

        Write-Host "-> Processing: $station_id ($config_name)"
        $row_record = Get-RiverRow $station_id $config_name
        if ($null -ne $row_record) {
            $all_station_rows += $row_record
        }
    }

    if ($all_station_rows.Count -gt 0) {
        $all_station_rows | Export-Csv -Path $OUTPUT_CSV_PATH -NoTypeInformation -Force
        Write-Host "`n[SUCCESS] Matrix generation complete. $($all_station_rows.Count) gages compiled in $OUTPUT_CSV_PATH"
    } else {
        Write-Error "No valid data could be compiled from configuration list."
    }
} else {
    Write-Error "[CRITICAL ERROR] Configuration file missing at: $CONFIG_FILE_PATH"
}