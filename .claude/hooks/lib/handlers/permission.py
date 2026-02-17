"""PermissionRequest hook handler for approval notifications."""

from ..audio import AudioSettings
from ..config import PermissionRequestHookConfig
from ..state import mark_handled
from .base import BaseHandler


class PermissionRequestHandler(BaseHandler):
    """Handler for the PermissionRequest hook event.

    Notifies when Claude needs permission to run a command.
    Marks state to prevent duplicate notifications from Stop hook.
    """

    @property
    def hook_config(self) -> PermissionRequestHookConfig:
        """Get permission_request-specific hook configuration."""
        return self.config.permission_request

    def should_handle(self, data: dict) -> bool:  # noqa: ARG002
        """Check if this handler should process the event."""
        return self.hook_config.enabled

    def get_audio_settings(self) -> AudioSettings:
        """Get audio settings for permission notification."""
        return AudioSettings(
            sound=self.hook_config.sound,
            voice=self.hook_config.voice,
        )

    def get_message(self, data: dict) -> str | None:
        """Extract tool name and format permission message.

        For AskUserQuestion, extracts the actual question text from tool_input
        so the user hears the question itself rather than "Approve AskUserQuestion?".
        """
        tool_name = (
            data.get("tool_name")
            or data.get("tool", {}).get("name")
            or "tool"
        )

        # Special case: speak the actual question for AskUserQuestion
        if tool_name == "AskUserQuestion":
            tool_input = data.get("tool_input", {})
            questions = tool_input.get("questions", [])
            if questions:
                first_q = questions[0].get("question", "")
                if first_q:
                    return first_q

        return self.hook_config.message_template.format(tool_name=tool_name)

    def _pre_message_hook(self, data: dict) -> None:
        """Mark as handled for deduplication before processing."""
        session_id = data.get("session_id", "")
        if session_id:
            mark_handled(session_id, "permission")
            self.log(f"marked_handled: permission for session {session_id}")
