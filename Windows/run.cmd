@echo off
setlocal enabledelayedexpansion

:: ============================================================================
:: ALIASES & CONFIGURATION
:: ============================================================================

:: Setup persistent aliases for this session
doskey ll=dir /a /o:d /4 $*
doskey cat=type $*
doskey ..=cd ..

:: --- Menu Configuration ---
:: Define menu items. Usage: call :configure_menu [Num] "[Title]" "[Path]" "[#HexColor]"
:: The hex color is optional. Leave it blank "" for the default terminal color.
call :configure_menu 1 "Image Gen Project Alpha" "D:\AI_PROJECTS\Project_Alpha" "#348AA7"
call :configure_menu 2 "Image Gen Project Beta"  "D:\AI_PROJECTS\Project_Beta"  "#BB169A"
call :configure_menu 3 "Image Gen Project Gamma" "D:\AI_PROJECTS\Project_Gamma" "#DC602E"
call :configure_menu 4 "Video Tool Delta"       "D:\VIDEO_TOOLS\Tool_Delta"     "#6AB04C"
call :configure_menu 5 "Training Tool Epsilon"  "D:\TRAINING_TOOLS\Tool_Epsilon" "#F0932B"
call :configure_menu 6 "Upscaling Tool Zeta"    "D:\GRAPHICS_TOOLS\Tool_Zeta"    "#C83349"
call :configure_menu 7 "Audio Tool Eta"         "D:\AUDIO_TOOLS\Tool_Eta"         "#30336B"
call :configure_menu 8 "Main Projects Drive"    "D:\"                          "#8BE9FD"
call :configure_menu 9 "User Home Directory"    "%USERPROFILE%"                "#928374"
set "MENU_COUNT=9"

:: ============================================================================
:: MAIN MENU LOGIC
:: ============================================================================
:main_menu
cls
echo ===================================
echo     Project Launcher
echo ===================================
echo.
call :display_menu
echo.
echo 0) Exit
echo.

:: Use 'choice' for robust menu selection.
choice /c:0123456789 /n /m "Select an option: "

:: Map ERRORLEVEL to the actual chosen number.
if %errorlevel% == 1 (
    set "choice=0"
) else (
    set /a "choice = %errorlevel% - 1"
)

:: Handle the selected choice
if "%choice%"=="0" (
    echo Exiting...
    timeout /t 1 /nobreak >nul
    goto :eof
)

set "target_title=!MENU_%choice%_TITLE!"
set "target_path=!MENU_%choice%_PATH!"
set "target_color=!MENU_%choice%_COLOR!"

call :launch "%target_title%" "%target_path%" "%target_color%"
goto :eof


:: ============================================================================
:: SUBROUTINES
:: ============================================================================

:configure_menu
:: Sets variables for a menu item.
set "MENU_%~1_TITLE=%~2"
set "MENU_%~1_PATH=%~3"
set "MENU_%~1_COLOR=%~4"
goto :eof

:display_menu
:: Dynamically displays the configured menu items
for /l %%i in (1, 1, %MENU_COUNT%) do (
    echo %%i^) !MENU_%%i_TITLE! -- ^(!MENU_%%i_PATH!^)
)
goto :eof

:launch
:: Opens a new Windows Terminal tab.
set "tab_title=%~1"
set "start_dir=%~2"
set "tab_color=%~3"
set "activate_script=%start_dir%\activate.bat"

:: Build the optional color argument for wt.exe
set "color_arg="
if defined tab_color (
    if not "%tab_color%"=="" (
        set "color_arg=--tabColor "%tab_color%""
    )
)

echo.
echo Launching "%tab_title%" in a new terminal tab...
echo Path: %start_dir%
if defined color_arg echo Color: %tab_color%
echo.

if exist "%activate_script%" (
    wt.exe -w 0 new-tab --title "%tab_title%" %color_arg% --startingDirectory "%start_dir%" cmd.exe /k "%activate_script%"
) else (
    wt.exe -w 0 new-tab --title "%tab_title%" %color_arg% --startingDirectory "%start_dir%"
)

timeout /t 1 /nobreak >nul
goto :eof

endlocal