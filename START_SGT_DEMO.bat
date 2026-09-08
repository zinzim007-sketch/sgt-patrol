@echo off
setlocal
title SGT PATROL - DEMO STARTUP

echo ==========================================
echo        SGT PATROL DEMO STARTUP
echo ==========================================
echo.

echo [1/2] Starting detector...

start "SGT DETECTOR" wsl.exe -d Ubuntu-22.04 bash -lc "cd /home/zinzi/safeguard_ws && source install/setup.bash && python3 detector.py --video '/mnt/c/Users/zinzi/Desktop/SGT work/sgt_patrol/assets/demo/patrol_demo.mp4'; echo; echo DETECTOR EXITED - press Enter to close; read"

timeout /t 5 /nobreak >nul

echo [2/2] Starting Flutter...
cd /d "%~dp0"
start "SGT FLUTTER" powershell -NoExit -Command "flutter run -d windows"

echo.
echo SGT is starting.
echo.

endlocal