@echo off

powershell -Command "Write-Host 'Iniciando el mundo ...' -ForegroundColor Magenta -BackgroundColor Black"
echo.
docker compose up -d
echo.
powershell -Command "Write-Host '(el terminal tardara 1 minuto en estar disponible a partir de que el servidor arranque).' -ForegroundColor Magenta -BackgroundColor Black"

pause