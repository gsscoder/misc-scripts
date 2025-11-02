<#
.SYNOPSIS
    Prints the folder and file structure in a tree-like format.

.DESCRIPTION
    Displays the directory structure recursively in a tree-like layout.
    When the -NoHidden switch is used, files and folders starting with '.' or '_'
    are excluded from output.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [switch]$NoHidden
)

function Show-Tree {
    param(
        [string]$Path,
        [string]$Prefix = "",
        [switch]$NoHidden
    )

    # Retrieve children
    $folders = Get-ChildItem -Path $Path -Directory -ErrorAction SilentlyContinue
    $files   = Get-ChildItem -Path $Path -File -ErrorAction SilentlyContinue

    # Apply NoHidden filter
    if ($NoHidden) {
        $folders = $folders | Where-Object { $_.Name -notmatch '^[._]' }
        $files   = $files   | Where-Object { $_.Name -notmatch '^[._]' }
    }

    # Print children (but NOT the folder name again — parent already printed it)
    if ($folders.Count -gt 0 -or $files.Count -gt 0) {
        Write-Output "$Prefix|"
    }

    foreach ($folder in $folders) {
        Write-Output "$Prefix|----$($folder.Name)"
        Show-Tree -Path $folder.FullName -Prefix "$Prefix|    " -NoHidden:$NoHidden
    }

    foreach ($file in $files) {
        Write-Output "$Prefix|----$($file.Name)"
    }
}

# Print the root folder name ONCE
$resolved = Resolve-Path $Path
Write-Output (Split-Path $resolved -Leaf)

Show-Tree -Path $resolved -NoHidden:$NoHidden
