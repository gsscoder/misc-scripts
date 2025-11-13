param(
    [Parameter(Mandatory=$true)]
    [string]$Directory
)

# Fail if directory exists
if (Test-Path -Path $Directory) {
    Write-Error "Directory '$Directory' already exists."
    exit 1
}

# Create directory
New-Item -ItemType Directory -Path $Directory | Out-Null
Set-Location -Path $Directory

# Create venv
python -m venv .venv

# Activate venv
& .\.venv\Scripts\Activate.ps1

# Install jupyterlab
pip install jupyterlab

# Freeze requirements
pip freeze > requirements.txt

# Add comment as first line
$content = @("# JupyterLab") + (Get-Content requirements.txt)
$content | Set-Content requirements.txt

Write-Host "Setup complete at $(Get-Location)"
