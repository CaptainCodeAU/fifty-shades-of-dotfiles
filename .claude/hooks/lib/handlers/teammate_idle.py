"""TeammateIdle hook handler for teammate idle notifications."""

from ..audio import AudioSettings
from ..config import TeammateIdleHookConfig
from .base import BaseHandler


class TeammateIdleHandler(BaseHandler):
    """Handler for the TeammateIdle hook event.

    Notifies when a teammate goes idle.
    """

    @property
    def hook_config(self) -> TeammateIdleHookConfig:
        """Get teammate_idle-specific hook configuration."""
        return self.config.teammate_idle

    def should_handle(self, data: dict) -> bool:  # noqa: ARG002
        """Check if this handler should process the event."""
        return self.hook_config.enabled

    def get_audio_settings(self) -> AudioSettings:
        """Get audio settings for teammate idle notification."""
        return AudioSettings(
            sound=self.hook_config.sound,
            voice=self.hook_config.voice,
        )

    def get_message(self, data: dict) -> str | None:
        """Format teammate idle message from template."""
        teammate_name = data.get("teammate_name", "teammate")
        return self.hook_config.message_template.format(teammate_name=teammate_name)
