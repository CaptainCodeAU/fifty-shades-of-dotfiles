@echo off

:: Setup aliases
doskey ll=dir /a /o:d /4 $*
doskey cat=type $*
doskey ..=cd ..

:: Check if the activation script exists before calling it
if exist "D:\DIR\Rounding\venv\Scripts\activate.bat" (
    call D:\DIR\Rounding\venv\Scripts\activate.bat
) else (
    echo "Warning: venv Activation script not found. Please ensure the virtual environment path is correct."
)

:: Set a colorful prompt only if VIRTUAL_ENV_PROMPT is set
:: Using ANSI escape codes for color. May not work on older versions of the Command Prompt.
prompt $E[92m%VIRTUAL_ENV_PROMPT%$E[36m$P$E[0m$G

:: Inform the user about the CLI command
echo CLI Command:
echo.
echo python Rounding.py
echo.
