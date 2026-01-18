"""Audio functionality for Claude Code hooks - sound effects and speech (macOS)."""

import os
import subprocess
import threading
import time
from dataclasses import dataclass

from .config import SoundConfig, VoiceConfig


# Volume restoration lock to prevent race conditions
_volume_lock = threading.Lock()
_current_restore_id: int | None = None


@dataclass
class AudioSettings:
    """Settings for audio playback."""

    sound: SoundConfig
    voice: VoiceConfig

    @classmethod
    def from_configs(cls, sound: SoundConfig, voice: VoiceConfig) -> "AudioSettings":
        """Create AudioSettings from SoundConfig and VoiceConfig."""
        return cls(sound=sound, voice=voice)


def play_sound(path: str, volume: float = 1.0, project_dir: str = "") -> bool:
    """Play a sound effect file using macOS afplay command.

    Args:
        path: Path to sound file (relative to project_dir or absolute)
        volume: Volume level (0.0 to 1.0)
        project_dir: Project directory for relative paths

    Returns:
        True if sound started playing, False otherwise
    """
    # Resolve path
    if not os.path.isabs(path) and project_dir:
        full_path = os.path.join(project_dir, path)
    else:
        full_path = path

    if not os.path.exists(full_path):
        return False

    # Clamp volume between 0.0 and 1.0
    volume = max(0.0, min(1.0, volume))

    try:
        subprocess.Popen(
            ["afplay", "-v", str(volume), full_path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        return True
    except (OSError, subprocess.SubprocessError):
        return False


def get_system_volume() -> float | None:
    """Get current macOS system volume.

    Returns:
        Volume level (0.0 to 1.0) or None if failed
    """
    try:
        result = subprocess.run(
            ["osascript", "-e", "output volume of (get volume settings)"],
            capture_output=True,
            text=True,
            timeout=1.0,
        )
        if result.returncode == 0:
            return float(result.stdout.strip()) / 100.0
    except (OSError, subprocess.SubprocessError, ValueError):
        pass
    return None


def set_system_volume(volume: float) -> float | None:
    """Set macOS system volume using AppleScript.

    Args:
        volume: Volume level (0.0 to 1.0)

    Returns:
        Previous volume level (0.0 to 1.0) or None if failed
    """
    # Clamp volume between 0.0 and 1.0
    volume = max(0.0, min(1.0, volume))

    # Get current volume first
    old_volume = get_system_volume()

    # Set new volume (0-100 scale for AppleScript)
    volume_percent = int(volume * 100)
    try:
        subprocess.run(
            ["osascript", "-e", f"set volume output volume {volume_percent}"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=1.0,
        )
    except (OSError, subprocess.SubprocessError):
        pass

    return old_volume


def estimate_speech_duration(text: str, rate: int) -> float:
    """Estimate speech duration in seconds based on text length and rate.

    Args:
        text: Text to speak
        rate: Words per minute

    Returns:
        Estimated duration in seconds
    """
    word_count = len(text.split())
    if word_count == 0:
        return 0.5  # Minimum duration

    # Calculate duration: words / (words per minute / 60 seconds per minute)
    duration = (word_count / rate) * 60
    # Add a small buffer for safety
    return duration + 0.5


def _restore_volume_after_delay(old_volume: float, delay_seconds: float, restore_id: int) -> None:
    """Restore system volume after a delay in a background thread.

    Args:
        old_volume: Volume to restore to
        delay_seconds: Delay before restoration
        restore_id: Unique ID for this restoration task
    """
    global _current_restore_id

    def restore():
        time.sleep(delay_seconds)
        with _volume_lock:
            global _current_restore_id
            # Only restore if this is still the active restoration task
            if _current_restore_id == restore_id:
                set_system_volume(old_volume)
                _current_restore_id = None

    thread = threading.Thread(target=restore, daemon=True)
    thread.start()


def speak(
    text: str,
    voice: str = "Victoria",
    rate: int = 280,
    volume: float = 1.0,
) -> bool:
    """Speak text using macOS say command.

    Args:
        text: Text to speak
        voice: macOS voice name
        rate: Words per minute
        volume: Voice volume (0.0 to 1.0)

    Returns:
        True if speech started, False otherwise
    """
    global _current_restore_id

    # Set system volume for voice (say command uses system volume)
    old_volume = None
    restore_id = None

    if volume != 1.0:
        with _volume_lock:
            old_volume = set_system_volume(volume)
            # Generate unique ID for this restoration
            restore_id = id(text) + int(time.time() * 1000000)
            _current_restore_id = restore_id

    # Escape single quotes for shell
    escaped_text = text.replace("'", "'\\''")

    try:
        subprocess.Popen(
            ["say", "-v", voice, "-r", str(rate), escaped_text],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

        # Restore volume after estimated speech duration
        if old_volume is not None and restore_id is not None:
            duration = estimate_speech_duration(text, rate)
            _restore_volume_after_delay(old_volume, duration, restore_id)

        return True
    except (OSError, subprocess.SubprocessError):
        # Restore volume immediately on error
        if old_volume is not None:
            with _volume_lock:
                set_system_volume(old_volume)
                _current_restore_id = None
        return False


def play_notification(
    message: str,
    settings: AudioSettings,
    project_dir: str = "",
) -> None:
    """Play a complete notification with optional sound and speech.

    Args:
        message: Text to speak
        settings: Audio settings with sound and voice configs
        project_dir: Project directory for relative paths
    """
    sound_played = False

    # Play sound effect if enabled
    if settings.sound.enabled and settings.sound.file:
        sound_played = play_sound(
            settings.sound.file,
            settings.sound.volume,
            project_dir,
        )

    # Speak the message if enabled
    if settings.voice.enabled:
        # Only delay if sound was played and we're about to speak
        if sound_played:
            time.sleep(settings.sound.delay_ms / 1000.0)
        speak(
            message,
            settings.voice.name,
            settings.voice.rate,
            settings.voice.volume,
        )
