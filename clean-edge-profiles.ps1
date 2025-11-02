# Clean Edge temporary files from all profiles except Default
$edgePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
$profiles = Get-ChildItem -Path $edgePath -Directory | Where-Object { $_.Name -like "Profile *" }

foreach ($profile in $profiles) {
    $cachePath = Join-Path $profile.FullName "Cache"
    $gpCachePath = Join-Path $profile.FullName "GPUCache"
    
    # Remove cache directories if they exist
    if (Test-Path $cachePath) {
        Remove-Item -Path $cachePath -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $gpCachePath) {
        Remove-Item -Path $gpCachePath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Edge temporary files cleaned from all profiles (except Default)"
