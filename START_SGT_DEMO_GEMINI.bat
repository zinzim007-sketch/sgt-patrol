@echo off
setlocal
title SGT PATROL - DEMO STARTUP

echo ==========================================
echo        SGT PATROL DEMO STARTUP
echo ==========================================
echo.

REM Loads MTX_PASS from mtx_secret.bat, which sits next to this file and
REM is NOT committed to git (see .gitignore). This is the only place the
REM real password lives — this script itself never contains it.
if not exist "%~dp0mtx_secret.bat" (
    echo ERROR: mtx_secret.bat not found next to this script.
    echo Create it with one line:  set MTX_PASS=your_mediamtx_password
    pause
    exit /b 1
)
call "%~dp0mtx_secret.bat"

if "%MTX_PASS%"=="" (
    echo ERROR: MTX_PASS is empty in mtx_secret.bat.
    pause
    exit /b 1
)

echo [1/3] Starting detector...

REM Live MediaMTX stream in place of the old assets/demo/patrol_demo.mp4.
REM RTSP on 8554 is MediaMTX's default port — confirm against your actual
REM mediamtx.yml if the detector fails to open the stream.
start "SGT DETECTOR" wsl.exe -d Ubuntu-22.04 bash -lc "cd /home/zinzi/safeguard_ws && source install/setup.bash && python3 detector.py --video 'rtsp://viewer:%MTX_PASS%@40.123.253.60:8554/live'; echo; echo DETECTOR EXITED - press Enter to close; read"

timeout /t 5 /nobreak >nul

echo [2/3] Starting Gemini AI bridge...

REM Gemini bridge connects to the detector on ws://localhost:8765,
REM sends the live video frames to Gemini Live, and exposes Gemini
REM intelligence to Flutter on ws://localhost:8767.
REM GEMINI_API_KEY is loaded from the WSL environment/.bashrc and is
REM intentionally NOT stored in this .bat file.
start "SGT GEMINI" wsl.exe -d Ubuntu-22.04 bash -lc "cd /home/zinzi/safeguard_ws && source install/setup.bash && python3 gemini_safeguard_bridge.py; echo; echo GEMINI BRIDGE EXITED - press Enter to close; read"

timeout /t 3 /nobreak >nul

echo [3/3] Starting Flutter...
cd /d "%~dp0"
start "SGT FLUTTER" powershell -NoExit -Command "flutter run -d windows"

echo.
echo SGT is starting: detector + Gemini Live + Flutter.
echo.

endlocal
