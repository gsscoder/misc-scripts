<#
.SYNOPSIS
    Removes dead "Open With" context menu entries from Windows Explorer.

.DESCRIPTION
    This script identifies and removes registry entries for applications that appear in 
    the "Open With" context menu but whose executables no longer exist on the filesystem.
    Can also force-remove entries for a specific application name.

.PARAMETER ApplicationName
    Optional. The executable name to search for and remove (e.g., "photoshop.exe").
    If not specified, scans all Open With entries and removes those pointing to non-existent files.

.PARAMETER Force
    When specified with ApplicationName, removes all entries for that app without checking 
    if the executable exists. Useful for stubborn entries.

.PARAMETER ScanAll
    Scans all Open With entries and removes those pointing to non-existent executables.

.PARAMETER WhatIf
    Shows what would be removed without actually removing it.

.EXAMPLE
    .\wipe-openwith-entry.ps1 -ScanAll
    Scans all Open With entries and removes dead links.

.EXAMPLE
    .\wipe-openwith-entry.ps1 -ApplicationName "photoshop.exe" -Force
    Removes all references to photoshop.exe regardless of whether it exists.

.EXAMPLE
    .\wipe-openwith-entry.ps1 -ApplicationName "oldapp.exe" -WhatIf
    Shows what would be removed for oldapp.exe without making changes.
#>

[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'ScanAll')]
param(
    [Parameter(ParameterSetName = 'ByName', Mandatory = $true)]
    [string]$ApplicationName,
    
    [Parameter(ParameterSetName = 'ByName')]
    [switch]$Force,
    
    [Parameter(ParameterSetName = 'ScanAll')]
    [switch]$ScanAll
)

# Check for admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Not running as administrator. System-wide (HKLM) entries will be skipped."
}

$script:entriesToRemove = @()
$script:processedPaths = @{}

function Test-ExecutableExists {
    param([string]$ExeName)
    
    # Try to find the executable in PATH
    $found = Get-Command $ExeName -ErrorAction SilentlyContinue
    if ($found) { return $true }
    
    # Check common installation directories
    $searchPaths = @(
        "$env:ProgramFiles",
        "${env:ProgramFiles(x86)}",
        "$env:LocalAppData\Programs"
    )
    
    foreach ($basePath in $searchPaths) {
        if (Test-Path $basePath) {
            $found = Get-ChildItem -Path $basePath -Filter $ExeName -Recurse -ErrorAction SilentlyContinue -Depth 3 | Select-Object -First 1
            if ($found) { return $true }
        }
    }
    
    return $false
}

function Get-ExecutableFromProgId {
    param([string]$ProgId)
    
    # Try to resolve ProgId to actual executable
    $shellOpenPath = "Registry::HKEY_CLASSES_ROOT\$ProgId\shell\open\command"
    if (Test-Path $shellOpenPath) {
        try {
            $command = (Get-ItemProperty -Path $shellOpenPath -Name '(Default)' -ErrorAction SilentlyContinue).'(Default)'
            if ($command) {
                # Extract executable from command (handle quotes and arguments)
                if ($command -match '^"([^"]+)"' -or $command -match '^([^\s]+)') {
                    return $matches[1]
                }
            }
        } catch {}
    }
    
    return $null
}

function Add-EntryForRemoval {
    param(
        [string]$Path,
        [string]$Type,
        [string]$Reason,
        [string]$Property = $null,
        [string]$Value = $null,
        [string]$Extension = $null
    )
    
    # Avoid duplicates
    $key = "$Path|$Property"
    if ($script:processedPaths.ContainsKey($key)) { return }
    $script:processedPaths[$key] = $true
    
    $script:entriesToRemove += [PSCustomObject]@{
        Path      = $Path
        Type      = $Type
        Reason    = $Reason
        Property  = $Property
        Value     = $Value
        Extension = $Extension
    }
}

function Process-OpenWithList {
    param(
        [string]$Path,
        [string]$Extension,
        [string]$TargetApp = $null,
        [bool]$CheckExists = $true
    )
    
    if (-not (Test-Path $Path)) { return }
    
    try {
        $values = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
        if (-not $values) { return }
        
        $valuesToRemove = @()
        $mruList = $values.MRUList
        
        # Process each value (typically named a, b, c, etc.)
        $props = $values.PSObject.Properties | Where-Object { 
            $_.Name -notlike "PS*" -and $_.Name -ne "MRUList" 
        }
        
        foreach ($prop in $props) {
            $exeName = $prop.Value
            if (-not $exeName) { continue }
            
            $shouldRemove = $false
            $reason = ""
            
            if ($TargetApp) {
                # Specific app mode
                if ($exeName -like "*$TargetApp*") {
                    $shouldRemove = $true
                    $reason = "Matches target application '$TargetApp'"
                }
            }
            elseif ($CheckExists) {
                # Scan mode - check if executable exists
                if (-not (Test-ExecutableExists -ExeName $exeName)) {
                    $shouldRemove = $true
                    $reason = "Executable '$exeName' not found on system"
                }
            }
            
            if ($shouldRemove) {
                Add-EntryForRemoval -Path $Path -Type "Registry Value" `
                    -Reason $reason -Property $prop.Name -Value $exeName -Extension $Extension
                $valuesToRemove += $prop.Name
            }
        }
        
        # If we removed values, we need to update MRUList
        if ($valuesToRemove.Count -gt 0 -and $mruList) {
            $newMRUList = $mruList
            foreach ($val in $valuesToRemove) {
                $newMRUList = $newMRUList -replace $val, ''
            }
            if ($newMRUList -ne $mruList) {
                Add-EntryForRemoval -Path $Path -Type "Registry Value" `
                    -Reason "Update MRUList after removing dead entries" `
                    -Property "MRUList" -Value $newMRUList -Extension $Extension
            }
        }
        
    } catch {
        Write-Verbose "Error processing OpenWithList at ${Path}: $($_.Exception.Message)"
    }
}

function Process-ApplicationEntry {
    param(
        [string]$AppKeyPath,
        [string]$AppName,
        [string]$TargetApp = $null,
        [bool]$CheckExists = $true
    )
    
    $shouldRemove = $false
    $reason = ""
    
    if ($TargetApp) {
        if ($AppName -like "*$TargetApp*") {
            $shouldRemove = $true
            $reason = "Application entry for '$TargetApp'"
        }
    }
    elseif ($CheckExists) {
        # Try to find the executable path from the application entry
        $commandPath = Join-Path $AppKeyPath "shell\open\command"
        if (Test-Path $commandPath) {
            try {
                $command = (Get-ItemProperty -Path $commandPath -Name '(Default)' -ErrorAction SilentlyContinue).'(Default)'
                if ($command) {
                    # Extract path from command
                    $exePath = $null
                    if ($command -match '^"([^"]+)"') {
                        $exePath = $matches[1]
                    }
                    elseif ($command -match '^([^\s]+)') {
                        $exePath = $matches[1]
                    }
                    
                    if ($exePath -and -not (Test-Path $exePath)) {
                        $shouldRemove = $true
                        $reason = "Executable path not found: $exePath"
                    }
                }
            } catch {}
        }
        else {
            # No command found, check if the app name itself exists
            if (-not (Test-ExecutableExists -ExeName $AppName)) {
                $shouldRemove = $true
                $reason = "Application '$AppName' not found on system"
            }
        }
    }
    
    if ($shouldRemove) {
        Add-EntryForRemoval -Path $AppKeyPath -Type "Registry Key" -Reason $reason
    }
}

# Main execution
if ($ApplicationName) {
    Write-Host "Searching for entries related to '$ApplicationName'..." -ForegroundColor Yellow
    $targetApp = $ApplicationName
    $checkExists = -not $Force
    
    if ($Force) {
        Write-Host "Force mode: Will remove all entries regardless of executable existence" -ForegroundColor Yellow
    }
}
else {
    Write-Host "Scanning all 'Open With' entries for dead links..." -ForegroundColor Yellow
    $targetApp = $null
    $checkExists = $true
}

# 1. Process HKCU:\Software\Classes\Applications
Write-Verbose "Scanning HKCU:\Software\Classes\Applications..."
$userAppsPath = "HKCU:\Software\Classes\Applications"
if (Test-Path $userAppsPath) {
    $apps = Get-ChildItem -Path $userAppsPath -ErrorAction SilentlyContinue
    foreach ($app in $apps) {
        Process-ApplicationEntry -AppKeyPath $app.PSPath -AppName $app.PSChildName `
            -TargetApp $targetApp -CheckExists $checkExists
    }
}

# 2. Process HKLM:\Software\Classes\Applications (requires admin)
if ($isAdmin) {
    Write-Verbose "Scanning HKLM:\Software\Classes\Applications..."
    $systemAppsPath = "HKLM:\Software\Classes\Applications"
    if (Test-Path $systemAppsPath) {
        $apps = Get-ChildItem -Path $systemAppsPath -ErrorAction SilentlyContinue
        foreach ($app in $apps) {
            Process-ApplicationEntry -AppKeyPath $app.PSPath -AppName $app.PSChildName `
                -TargetApp $targetApp -CheckExists $checkExists
        }
    }
}

# 3. Process FileExts OpenWithList entries
Write-Verbose "Scanning file extension Open With lists..."
$fileExtsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts"
if (Test-Path $fileExtsPath) {
    $extensions = Get-ChildItem -Path $fileExtsPath -ErrorAction SilentlyContinue
    
    foreach ($ext in $extensions) {
        $openWithListPath = Join-Path $ext.PSPath "OpenWithList"
        Process-OpenWithList -Path $openWithListPath -Extension $ext.PSChildName `
            -TargetApp $targetApp -CheckExists $checkExists
        
        # Also check OpenWithProgids
        $openWithProgidsPath = Join-Path $ext.PSPath "OpenWithProgids"
        if (Test-Path $openWithProgidsPath) {
            try {
                $progids = Get-ItemProperty -Path $openWithProgidsPath -ErrorAction SilentlyContinue
                if ($progids) {
                    $props = $progids.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" }
                    foreach ($prop in $props) {
                        $shouldRemove = $false
                        if ($targetApp -and $prop.Name -like "*$targetApp*") {
                            $shouldRemove = $true
                        }
                        elseif ($checkExists) {
                            $exePath = Get-ExecutableFromProgId -ProgId $prop.Name
                            if ($exePath -and -not (Test-Path $exePath)) {
                                $shouldRemove = $true
                            }
                        }
                        
                        if ($shouldRemove) {
                            Add-EntryForRemoval -Path $openWithProgidsPath -Type "Registry Value" `
                                -Reason "Dead ProgId reference" -Property $prop.Name `
                                -Value $prop.Value -Extension $ext.PSChildName
                        }
                    }
                }
            } catch {
                Write-Verbose "Error processing OpenWithProgids for $($ext.PSChildName)"
            }
        }
    }
}

# 4. Process SystemFileAssociations (requires admin)
if ($isAdmin) {
    Write-Verbose "Scanning system file associations..."
    $systemAssocPath = "HKLM:\Software\Classes\SystemFileAssociations"
    if (Test-Path $systemAssocPath) {
        $associations = Get-ChildItem -Path $systemAssocPath -ErrorAction SilentlyContinue
        foreach ($assoc in $associations) {
            $openWithListPath = Join-Path $assoc.PSPath "OpenWithList"
            Process-OpenWithList -Path $openWithListPath -Extension $assoc.PSChildName `
                -TargetApp $targetApp -CheckExists $checkExists
        }
    }
}

# Display results
if ($entriesToRemove.Count -eq 0) {
    Write-Host "`nNo dead or matching entries found." -ForegroundColor Green
    return
}

Write-Host "`nFound $($entriesToRemove.Count) entries to remove:" -ForegroundColor Yellow
Write-Host ""

# Group by extension for better readability
$grouped = $entriesToRemove | Group-Object Extension | Sort-Object Name
foreach ($group in $grouped) {
    if ($group.Name) {
        Write-Host "Extension: $($group.Name)" -ForegroundColor Cyan
    }
    else {
        Write-Host "Application Registrations:" -ForegroundColor Cyan
    }
    
    foreach ($entry in $group.Group) {
        Write-Host "  [$($entry.Type)]" -ForegroundColor DarkCyan -NoNewline
        if ($entry.Property) {
            Write-Host " Property '$($entry.Property)' = '$($entry.Value)'" -ForegroundColor Gray
        }
        else {
            Write-Host " $($entry.Path -replace '.*\\', '')" -ForegroundColor Gray
        }
        Write-Host "    Path: $($entry.Path)" -ForegroundColor DarkGray
        Write-Host "    Reason: $($entry.Reason)" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# Confirm and remove
if (-not $PSCmdlet.ShouldProcess("$($entriesToRemove.Count) registry entries", "Remove")) {
    Write-Host "No changes were made." -ForegroundColor Green
    return
}

Write-Host "Removing entries..." -ForegroundColor Yellow
$removedCount = 0
$failedCount = 0

# Group removals to handle MRUList updates properly
$removalsByPath = $entriesToRemove | Group-Object Path

foreach ($group in $removalsByPath) {
    $path = $group.Name
    $entries = $group.Group

    try {
        if (-not (Test-Path $path)) {
            Write-Verbose "Path no longer exists: $path"
            continue
        }

        # Handle registry keys (remove entire key)
        $keyRemovals = $entries | Where-Object { $_.Type -eq "Registry Key" }
        if ($keyRemovals) {
            Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
            Write-Host "  [OK] Removed: $path" -ForegroundColor Green
            $removedCount += $keyRemovals.Count
            continue
        }

        # Handle registry values (remove specific properties)
        $valueRemovals = $entries | Where-Object { $_.Type -eq "Registry Value" }

        # Handle MRUList specially
        $mruUpdate = $valueRemovals | Where-Object { $_.Property -eq "MRUList" }
        $otherValues = $valueRemovals | Where-Object { $_.Property -ne "MRUList" }

        foreach ($entry in $otherValues) {
            Remove-ItemProperty -Path $path -Name $entry.Property -Force -ErrorAction Stop
            Write-Host "  [OK] Removed '$($entry.Property)' from: $path" -ForegroundColor Green
            $removedCount++
        }

        # Update MRUList last
        if ($mruUpdate) {
            Set-ItemProperty -Path $path -Name "MRUList" -Value $mruUpdate.Value -Force -ErrorAction Stop
            Write-Host "  [OK] Updated MRUList in: $path" -ForegroundColor Green
            $removedCount++
        }
    }
    catch {
        Write-Warning "  [FAIL] Failed to process $path : $($_.Exception.Message)"
        $failedCount += $entries.Count
    }
}

Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Removed: $removedCount entries" -ForegroundColor Green
if ($failedCount -gt 0) {
    Write-Host "  Failed: $failedCount entries" -ForegroundColor Red
    Write-Host "  Try running as administrator for system-wide entries" -ForegroundColor Yellow
}

Write-Host "`nRefresh Windows Explorer to see changes:" -ForegroundColor Yellow
Write-Host "  - Restart Explorer: taskkill /f /im explorer.exe; start explorer.exe" -ForegroundColor White
Write-Host "  - Or restart your computer" -ForegroundColor White
