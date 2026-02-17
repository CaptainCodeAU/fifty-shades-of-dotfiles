"""PostToolUseFailure hook handler for tool failure notifications."""

from ..audio import AudioSettings
from ..config import PostToolUseFailureHookConfig
from ..state import mark_handled
from .base import BaseHandler


class PostToolUseFailureHandler(BaseHandler):
    """Handler for the PostToolUseFailure hook event.

    Notifies when a tool use fails. Skips user-caused interruptions.
    """

    @property
    def hook_config(self) -> PostToolUseFailureHookConfig:
        """Get tool_failure-specific hook configuration."""
        return self.config.post_tool_use_failure

    def should_handle(self, data: dict) -> bool:
        """Check if this handler should process the event.

        Returns False for user-caused interruptions (is_interrupt=True).
        """
        if not self.hook_config.enabled:
            return False
        # Skip user-caused interruptions — not a real failure
        if data.get("is_interrupt", False):
            self.log("is_interrupt: True - skipping")
            return False
        return True

    def get_audio_settings(self) -> AudioSettings:
        """Get audio settings for tool failure notification."""
        return AudioSettings(
            sound=self.hook_config.sound,
            voice=self.hook_config.voice,
        )

    def get_message(self, data: dict) -> str | None:
        """Format tool failure message from template."""
        tool_name = data.get("tool_name", "tool")
        return self.hook_config.message_template.format(tool_name=tool_name)

    def _pre_message_hook(self, data: dict) -> None:
        """Mark as handled for Stop dedup."""
        session_id = data.get("session_id", "")
        if session_id:
            mark_handled(session_id, "tool_failure")
            self.log(f"marked_handled: tool_failure for session {session_id}")
