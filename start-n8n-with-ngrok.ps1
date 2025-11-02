# start-n8n-with-ngrok.ps1

# Stop and remove existing container
docker stop n8n 2>$null | Out-Null
docker rm n8n 2>$null | Out-Null

# Start ngrok
Write-Host "Starting ngrok tunnel..." -ForegroundColor Cyan
$ngrokProcess = Start-Process -FilePath "ngrok" -ArgumentList "http 5678" -PassThru -WindowStyle Hidden

Start-Sleep -Seconds 3

# Get ngrok public URL
try {
    $response = Invoke-RestMethod -Uri "http://localhost:4040/api/tunnels" -TimeoutSec 5
    $ngrokUrl = $response.tunnels[0].public_url
    if (-not $ngrokUrl) { throw "No URL" }
} catch {
    Write-Host "ERROR: Could not get ngrok URL. Is ngrok running and authenticated?" -ForegroundColor Red
    exit 1
}

Write-Host "ngrok URL: $ngrokUrl" -ForegroundColor Green

# Start n8n with EXPLICIT volume: n8n_data -> /home/node/.n8n
Write-Host "Starting n8n with volume 'n8n_data'..." -ForegroundColor Cyan
docker run -d `
  --name n8n `
  -p 5678:5678 `
  -v n8n_data:/home/node/.n8n `
  -e WEBHOOK_URL="$ngrokUrl/" `
  docker.n8n.io/n8nio/n8n:latest | Out-Null

Write-Host ""
Write-Host "SUCCESS: n8n is running!" -ForegroundColor Green
Write-Host "UI: http://localhost:5678"
Write-Host "Webhook URL: $ngrokUrl" -ForegroundColor Yellow
Write-Host ""
Write-Host "Press Ctrl+C to stop." -ForegroundColor Gray

# Keep alive and clean up on exit
try {
    while ($true) { Start-Sleep -Seconds 5 }
} finally {
    Write-Host "`nShutting down..." -ForegroundColor Cyan
    docker stop n8n 2>$null | Out-Null
    docker rm n8n 2>$null | Out-Null
    if ($ngrokProcess -and !$ngrokProcess.HasExited) {
        Stop-Process -Id $ngrokProcess.Id -Force 2>$null
    }
}
