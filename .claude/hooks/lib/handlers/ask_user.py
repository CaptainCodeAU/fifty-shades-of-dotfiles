"""AskUserQuestion hook handler for question notifications."""

from ..audio import AudioSettings
from ..config import AskUserQuestionHookConfig
from ..state import mark_handled
from .base import BaseHandler


class AskUserQuestionHandler(BaseHandler):
    """Handler for the AskUserQuestion tool event.

    Notifies when Claude asks the user a question.
    Marks state to prevent duplicate notifications from Stop hook.
    """

    @property
    def hook_config(self) -> AskUserQuestionHookConfig:
        """Get ask_user_question-specific hook configuration."""
        return self.config.ask_user_question

    def should_handle(self, data: dict) -> bool:
        """Check if this handler should process the event."""
        if not self.hook_config.enabled:
            return False

        # Verify this is an AskUserQuestion tool event
        tool_name = data.get("tool_name", "")
        return tool_name == "AskUserQuestion"

    def get_audio_settings(self) -> AudioSettings:
        """Get audio settings for question notification."""
        return AudioSettings(
            sound=self.hook_config.sound,
            voice=self.hook_config.voice,
        )

    def get_message(self, data: dict) -> str | None:
        """Extract question from tool input."""
        tool_input = data.get("tool_input", {})

        if self.hook_config.message_mode == "extract":
            # Try to extract the actual question
            questions = tool_input.get("questions", [])
            if questions:
                first_q = questions[0].get("question", "")
                if first_q:
                    return first_q

        # Fall back to default message
        return self.hook_config.default_message

    def _pre_message_hook(self, data: dict) -> None:
        """Mark as handled for deduplication before processing."""
        session_id = data.get("session_id", "")
        if session_id:
            mark_handled(session_id, "ask_user")
            self.log(f"marked_handled: ask_user for session {session_id}")
