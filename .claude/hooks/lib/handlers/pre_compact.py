"""PreCompact hook handler for context compaction notifications."""

from ..audio import AudioSettings
from ..config import PreCompactHookConfig
from .base import BaseHandler


class PreCompactHandler(BaseHandler):
    """Handler for the PreCompact hook event.

    Notifies when context is about to be compacted.
    """

    @property
    def hook_config(self) -> PreCompactHookConfig:
        """Get pre_compact-specific hook configuration."""
        return self.config.pre_compact

    def should_handle(self, data: dict) -> bool:  # noqa: ARG002
        """Check if this handler should process the event."""
        return self.hook_config.enabled

    def get_audio_settings(self) -> AudioSettings:
        """Get audio settings for pre-compact notification."""
        return AudioSettings(
            sound=self.hook_config.sound,
            voice=self.hook_config.voice,
        )

    def get_message(self, data: dict) -> str | None:  # noqa: ARG002
        """Return static compaction message."""
        return self.hook_config.message
