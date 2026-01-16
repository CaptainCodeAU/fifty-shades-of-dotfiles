@echo off
setlocal

:: ============================================================================
:: Project Activation Script for: LoRA Trainer
:: ============================================================================

:: --- Configuration ---
set "VIRTUAL_ENV_PROMPT=(trainer_project)"
set "ADDITIONAL_PATHS=%~dp0venv\Lib\site-packages\torch\lib"

:: --- Environment Setup ---
cls

:: 1. Setup helpful aliases for the session.
echo [SETUP] Configuring session aliases (ll, cat, ..)...
doskey ll=dir /a /o:d /4 $*
doskey cat=type $*
doskey ..=cd ..

:: 2. Activate Python virtual environment.
set "VENV_PATH=%~dp0venv\Scripts\activate.bat"
echo [SETUP] Activating virtual environment...
if exist "%VENV_PATH%" (
    call "%VENV_PATH%"
) else (
    echo [WARNING] Virtual environment not found at "%VENV_PATH%".
)

:: 3. Add project-specific directories to the PATH.
if defined ADDITIONAL_PATHS (
    echo [SETUP] Adding project-specific directories to PATH...
    set "PATH=%ADDITIONAL_PATHS%;%PATH%"
)

:: 4. Run project-specific validation scripts.
if exist "%~dp0setup\validate_requirements.py" (
    echo [SETUP] Validating requirements...
    python.exe .\setup\validate_requirements.py
)

:: 5. Customize the command prompt.
prompt $E[92m%VIRTUAL_ENV_PROMPT% $E[36m$P$E[0m$G

echo.
echo ============================================================================
echo  Project environment for '%VIRTUAL_ENV_PROMPT%' is ready.
echo ============================================================================
echo.

:: ============================================================================
:: USAGE EXAMPLES
:: ============================================================================

echo [INFO] Example command to start the GUI:
echo(
echo   python.exe kohya_gui.py
echo(


echo [INFO] Example LoRA Training Command (EDIT PATHS BELOW):
echo(
echo   accelerate launch --num_cpu_threads_per_process=2 "./sdxl_train_network.py" ^
echo     --enable_bucket --min_bucket_reso=256 --max_bucket_reso=2048 ^
echo     --pretrained_model_name_or_path="C:\path\to\your\sd_xl_base_1.0.safetensors" ^
echo     --train_data_dir="C:\path\to\your\training_data\img" ^
echo     --reg_data_dir="C:\path\to\your\regularization_data\reg" ^
echo     --resolution="1024,1024" ^
echo     --output_dir="C:\path\to\your\output\model" ^
echo     --logging_dir="C:\path\to\your\output\log" ^
echo     --network_alpha="1" ^
echo     --save_model_as=safetensors ^
echo     --network_module=networks.lora ^
echo     --text_encoder_lr=0.0003 ^
echo     --unet_lr=0.0003 ^
echo     --network_dim=256 ^
echo     --output_name="MyCustomLoRA" ^
echo     --lr_scheduler_num_cycles="10" ^
echo     --no_half_vae ^
echo     --learning_rate="0.0003" ^
echo     --lr_scheduler="constant" ^
echo     --train_batch_size="1" ^
echo     --max_train_steps="10000" ^
echo     --save_every_n_epochs="1" ^
echo     --mixed_precision="bf16" ^
echo     --save_precision="bf16" ^
echo     --caption_extension=".txt" ^
echo     --cache_latents --cache_latents_to_disk ^
echo     --optimizer_type="Adafactor" ^
echo     --optimizer_args scale_parameter=False relative_step=False warmup_init=False ^
echo     --max_data_loader_n_workers="0" ^
echo     --bucket_reso_steps=64 ^
echo     --gradient_checkpointing ^
echo     --xformers ^
echo     --bucket_no_upscale ^
echo     --noise_offset=0.0
echo(