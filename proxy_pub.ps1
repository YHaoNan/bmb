$env:HTTP_PROXY = "http://localhost:7890"
$env:HTTPS_PROXY = "http://localhost:7890"
$env:NO_PROXY = "localhost,127.0.0.1"

Write-Host "✅ Proxy set to => http://localhost:7890" -ForegroundColor Green
Write-Host ""
Write-Host "🚀 Installing dependencies..." -ForegroundColor Cyan
flutter pub get
