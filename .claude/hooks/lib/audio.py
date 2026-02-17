"""Audio functionality for Claude Code hooks - sound effects and speech (macOS)."""

import os
import subprocess
import threading
import time
from dataclasses import dataclass

from .config import SoundConfig, VoiceConfig


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


def speak(
    text: str,
    voice: str = "Victoria",
    rate: int = 280,
    volume: float = 1.0,
) -> bool:
    """Speak text using macOS say command with per-process volume control.

    Renders speech to a temp file with `say -o`, then plays it with `afplay -v`
    for volume control without touching the global system volume.

    Args:
        text: Text to speak
        voice: macOS voice name
        rate: Words per minute
        volume: Voice volume (0.0 to 1.0)

    Returns:
        True if speech started, False otherwise
    """
    import tempfile

    with tempfile.NamedTemporaryFile(suffix=".aiff", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        result = subprocess.run(
            ["say", "-v", voice, "-r", str(rate), "-o", tmp_path, text],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=10.0,
        )
        if result.returncode != 0:
            os.unlink(tmp_path)
            return False

        subprocess.Popen(
            ["afplay", "-v", str(volume), tmp_path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

        def cleanup():
            time.sleep(30)
            try:
                os.unlink(tmp_path)
            except OSError:
                pass

        threading.Thread(target=cleanup, daemon=True).start()
        return True
    except (OSError, subprocess.SubprocessError, subprocess.TimeoutExpired):
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
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
