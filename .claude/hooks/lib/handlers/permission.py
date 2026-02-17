"""PermissionRequest hook handler for approval notifications."""

from ..audio import AudioSettings
from ..config import PermissionRequestHookConfig
from ..state import mark_handled, set_last_spoken, was_already_spoken
from ..summary import SummaryConfig, extract_summary
from ..transcript import get_transcript_path, read_last_assistant_text
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

        # Try to read the assistant's last text from the transcript.
        # We use read_last_assistant_text (not read_transcript) because
        # the very last assistant message may be a tool-only block with
        # no prose — we want the most recent message that has text.
        transcript_path, fallback_used = get_transcript_path(data, self.project_dir)
        self.log(f"transcript_path: {transcript_path}")
        self.log(f"fallback_used: {fallback_used}")
        if transcript_path:
            text = read_last_assistant_text(transcript_path)
            self.log(f"text_preview: {(text or '')[:200]}")
            if text:
                summary_cfg = self.config.stop.summary
                config = SummaryConfig(
                    mode=summary_cfg.mode,
                    max_sentences=summary_cfg.max_sentences,
                    max_characters=summary_cfg.max_characters,
                    start=summary_cfg.start,
                )
                summary = extract_summary(text, config)
                self.log(f"summary: {summary}")
                if summary:
                    session_id = data.get("session_id", "")
                    if session_id and was_already_spoken(session_id, summary):
                        self.log("summary already spoken — falling back to template")
                        return self.hook_config.message_template.format(tool_name=tool_name)
                    if session_id:
                        set_last_spoken(session_id, summary)
                    return summary

        return self.hook_config.message_template.format(tool_name=tool_name)

    def _pre_message_hook(self, data: dict) -> None:
        """Mark as handled for deduplication before processing."""
        session_id = data.get("session_id", "")
        if session_id:
            mark_handled(session_id, "permission")
            self.log(f"marked_handled: permission for session {session_id}")
