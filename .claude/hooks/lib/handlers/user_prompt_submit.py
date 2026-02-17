"""UserPromptSubmit hook handler (disabled by default)."""

from ..audio import AudioSettings
from ..config import UserPromptSubmitHookConfig
from .base import BaseHandler


class UserPromptSubmitHandler(BaseHandler):
    """Handler for the UserPromptSubmit hook event.

    Disabled by default — playing audio on your own input is redundant.
    Exists as a skeleton for future use.
    """

    @property
    def hook_config(self) -> UserPromptSubmitHookConfig:
        """Get user_prompt_submit-specific hook configuration."""
        return self.config.user_prompt_submit

    def should_handle(self, data: dict) -> bool:  # noqa: ARG002
        """Check if this handler should process the event."""
        return self.hook_config.enabled

    def get_audio_settings(self) -> AudioSettings:
        """Get audio settings for user prompt submit notification."""
        return AudioSettings(
            sound=self.hook_config.sound,
            voice=self.hook_config.voice,
        )

    def get_message(self, data: dict) -> str | None:  # noqa: ARG002
        """Return None — silent by design."""
        return None
