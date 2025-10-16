<#
.SYNOPSIS
    Prints the folder and file structure in a tree-like format.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

function Show-Tree {
    param(
        [string]$Path,
        [string]$Prefix = ""
    )

    $folders = Get-ChildItem -Path $Path -Directory -ErrorAction SilentlyContinue
    $files   = Get-ChildItem -Path $Path -File -ErrorAction SilentlyContinue

    # Print children (but NOT the folder name again — parent already printed it)
    if ($folders.Count -gt 0 -or $files.Count -gt 0) {
        Write-Output "$Prefix|"
    }

    foreach ($folder in $folders) {
        Write-Output "$Prefix|----$($folder.Name)"
        Show-Tree -Path $folder.FullName -Prefix "$Prefix|    "
    }

    foreach ($file in $files) {
        Write-Output "$Prefix|----$($file.Name)"
    }
}

# Print the root folder name ONCE
$resolved = Resolve-Path $Path
Write-Output (Split-Path $resolved -Leaf)

Show-Tree -Path $resolved
