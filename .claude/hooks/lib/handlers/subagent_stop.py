"""SubagentStop hook handler for subagent completion notifications."""

from ..audio import AudioSettings
from ..config import SubagentStopHookConfig
from ..state import mark_handled
from .base import BaseHandler


class SubagentStopHandler(BaseHandler):
    """Handler for the SubagentStop hook event.

    Notifies when a subagent finishes.
    """

    @property
    def hook_config(self) -> SubagentStopHookConfig:
        """Get subagent_stop-specific hook configuration."""
        return self.config.subagent_stop

    def should_handle(self, data: dict) -> bool:  # noqa: ARG002
        """Check if this handler should process the event."""
        return self.hook_config.enabled

    def get_audio_settings(self) -> AudioSettings:
        """Get audio settings for subagent stop notification."""
        return AudioSettings(
            sound=self.hook_config.sound,
            voice=self.hook_config.voice,
        )

    def get_message(self, data: dict) -> str | None:
        """Format subagent stop message from template."""
        agent_type = data.get("agent_type", "unknown")
        return self.hook_config.message_template.format(agent_type=agent_type)

    def _pre_message_hook(self, data: dict) -> None:
        """Mark as handled for Stop dedup."""
        session_id = data.get("session_id", "")
        if session_id:
            mark_handled(session_id, "subagent_stop")
            self.log(f"marked_handled: subagent_stop for session {session_id}")
