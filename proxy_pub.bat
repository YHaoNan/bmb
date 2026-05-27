@echo off

set HTTP_PROXY=http://localhost:7890
set HTTPS_PROXY=http://localhost:7890
set NO_PROXY=localhost,127.0.0.1

echo ✅ Proxy Set To http://localhost:7890
echo.
echo 🚀 Installing Dependencies...
flutter pub get
