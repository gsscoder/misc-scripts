<#
.SYNOPSIS
    Removes MEGA Sync leftover folders from Windows Explorer by cleaning registry entries.

.DESCRIPTION
    This script identifies and removes registry entries related to MEGA Sync that create
    phantom folders in Windows Explorer. It targets specific registry locations known
    to store shell namespace extensions to avoid lengthy full-system scans.

.PARAMETER WhatIf
    Shows what would be removed without actually removing it.

.PARAMETER Confirm
    Prompts for confirmation before removing registry entries.

.EXAMPLE
    .\wipeMegaLeftovers.ps1

.EXAMPLE
    .\wipeMegaLeftovers.ps1 -WhatIf

.EXAMPLE
    .\wipeMegaLeftovers.ps1 -Confirm:$false
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param()

# Define the registry locations where MEGA Sync typically stores its namespace extension entries
$registryPaths = @(
    "HKCU:\Software\Classes\CLSID",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace",
    "HKLM:\Software\Classes\CLSID",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
)

Write-Host "Scanning for MEGA Sync registry entries..." -ForegroundColor Yellow

$megaEntries = @()
$foundCount = 0

foreach ($path in $registryPaths) {
    Write-Verbose "Scanning: $path"
    
    # Check if the registry path exists
    if (Test-Path $path) {
        try {
            # Get subkeys that might contain MEGA entries
            $subKeys = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
            
            foreach ($subKey in $subKeys) {
                # Check if the subkey name or value contains "MEGA"
                if ($subKey.Name -match "MEGA") {
                    # Get the default value of the subkey to see if it contains MEGA
                    $defaultValue = $null
                    try {
                        $defaultValue = (Get-ItemProperty -Path $subKey.PSPath -ErrorAction SilentlyContinue)."(default)"
                    } catch {
                        # If default value access fails, continue to next
                        continue
                    }
                    
                    if ($defaultValue -and $defaultValue -match "MEGA") {
                        $megaEntries += [PSCustomObject]@{
                            Path = $subKey.PSPath
                            Name = $subKey.Name.Split('\')[-1]
                            Value = $defaultValue
                            Location = $path
                        }
                        $foundCount++
                    }
                } else {
                    # Even if the key name doesn't match, check its default value
                    $defaultValue = $null
                    try {
                        $defaultValue = (Get-ItemProperty -Path $subKey.PSPath -ErrorAction SilentlyContinue)."(default)"
                    } catch {
                        continue
                    }
                    
                    if ($defaultValue -and $defaultValue -match "MEGA") {
                        $megaEntries += [PSCustomObject]@{
                            Path = $subKey.PSPath
                            Name = $subKey.Name.Split('\')[-1]
                            Value = $defaultValue
                            Location = $path
                        }
                        $foundCount++
                    }
                }
            }
        } catch {
            Write-Warning "Could not access $path : $($_.Exception.Message)"
        }
    }
}

# Also check for MEGA entries in the Shell Extensions
$shellExtPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved"
if (Test-Path $shellExtPath) {
    try {
        $shellExtItems = Get-ChildItem -Path $shellExtPath -ErrorAction SilentlyContinue
        foreach ($item in $shellExtItems) {
            $itemValue = $null
            try {
                $itemValue = (Get-ItemProperty -Path $item.PSPath -ErrorAction SilentlyContinue)."(default)"
            } catch {
                continue
            }
            
            if ($itemValue -and $itemValue -match "MEGA") {
                $megaEntries += [PSCustomObject]@{
                    Path = $item.PSPath
                    Name = $item.Name.Split('\')[-1]
                    Value = $itemValue
                    Location = $shellExtPath
                }
                $foundCount++
            }
        }
    } catch {
        Write-Warning "Could not access $shellExtPath : $($_.Exception.Message)"
    }
}

if ($megaEntries.Count -eq 0) {
    Write-Host "No MEGA Sync registry entries found." -ForegroundColor Green
    Write-Host "Checking for MEGA folders in common locations..." -ForegroundColor Yellow
    
    # Check for MEGA folders in common locations
    $commonLocations = @(
        "$env:USERPROFILE\Desktop",
        "$env:USERPROFILE\Documents",
        "$env:USERPROFILE\OneDrive\Desktop",
        "$env:PUBLIC\Desktop"
    )
    
    $megaFolders = @()
    foreach ($location in $commonLocations) {
        if (Test-Path $location) {
            $folders = Get-ChildItem -Path $location -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "MEGA_*" }
            $megaFolders += $folders
        }
    }
    
    if ($megaFolders.Count -gt 0) {
        Write-Host "Found $($megaFolders.Count) MEGA-related folders:" -ForegroundColor Yellow
        foreach ($folder in $megaFolders) {
            Write-Host "  - $($folder.FullName)" -ForegroundColor Cyan
        }
        
        $removeFolders = $PSCmdlet.ShouldProcess("MEGA folders", "Remove")
        if ($removeFolders) {
            foreach ($folder in $megaFolders) {
                try {
                    Remove-Item -Path $folder.FullName -Recurse -Force -ErrorAction Stop
                    Write-Host "Removed folder: $($folder.FullName)" -ForegroundColor Green
                } catch {
                    Write-Warning "Could not remove folder $($folder.FullName): $($_.Exception.Message)"
                }
            }
        }
    } else {
        Write-Host "No MEGA folders found in common locations." -ForegroundColor Green
    }
    
    return
}

Write-Host "Found $foundCount MEGA Sync registry entries:" -ForegroundColor Yellow

foreach ($entry in $megaEntries) {
    Write-Host "  Registry Key: $($entry.Path)" -ForegroundColor Cyan
    Write-Host "  Default Value: $($entry.Value)" -ForegroundColor Gray
    Write-Host "  Location: $($entry.Location)" -ForegroundColor DarkGray
    Write-Host ""
}

# Confirm removal
if ($megaEntries.Count -gt 0) {
    $removeEntries = $PSCmdlet.ShouldProcess("MEGA registry entries", "Remove")
    
    if ($removeEntries) {
        Write-Host "Removing MEGA Sync registry entries..." -ForegroundColor Yellow
        
        $removedCount = 0
        foreach ($entry in $megaEntries) {
            try {
                Remove-Item -Path $entry.Path -Recurse -Force -ErrorAction Stop
                Write-Host "Successfully removed: $($entry.Path)" -ForegroundColor Green
                $removedCount++
            } catch {
                Write-Warning "Failed to remove $($entry.Path): $($_.Exception.Message)"
            }
        }
        
        Write-Host "Successfully removed $removedCount registry entries." -ForegroundColor Green
        
        # Suggest restarting Explorer to apply changes
        Write-Host "To see changes in Windows Explorer, you may need to:" -ForegroundColor Yellow
        Write-Host "1. Restart Windows Explorer (Task Manager -> Details tab -> right-click explorer.exe -> Restart)" -ForegroundColor White
        Write-Host "2. Or restart your computer." -ForegroundColor White
    }
} else {
    Write-Host "No changes were made to the registry." -ForegroundColor Green
}