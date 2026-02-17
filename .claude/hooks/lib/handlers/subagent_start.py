"""SubagentStart hook handler for subagent launch notifications."""

from ..audio import AudioSettings
from ..config import SubagentStartHookConfig
from .base import BaseHandler


class SubagentStartHandler(BaseHandler):
    """Handler for the SubagentStart hook event.

    Notifies when a subagent is launched.
    """

    @property
    def hook_config(self) -> SubagentStartHookConfig:
        """Get subagent_start-specific hook configuration."""
        return self.config.subagent_start

    def should_handle(self, data: dict) -> bool:  # noqa: ARG002
        """Check if this handler should process the event."""
        return self.hook_config.enabled

    def get_audio_settings(self) -> AudioSettings:
        """Get audio settings for subagent start notification."""
        return AudioSettings(
            sound=self.hook_config.sound,
            voice=self.hook_config.voice,
        )

    def get_message(self, data: dict) -> str | None:
        """Format subagent start message from template."""
        agent_type = data.get("agent_type", "unknown")
        return self.hook_config.message_template.format(agent_type=agent_type)
