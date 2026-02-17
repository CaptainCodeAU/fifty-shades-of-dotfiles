"""Stop hook handler for task completion notifications."""

import json

from ..audio import AudioSettings
from ..config import StopHookConfig
from ..state import was_handled
from ..summary import SummaryConfig, extract_last_question, extract_summary
from ..transcript import MessageInfo, get_transcript_path, read_last_assistant_text, read_transcript
from .base import BaseHandler


class StopHandler(BaseHandler):
    """Handler for the Stop hook event.

    Notifies when Claude completes a task or is waiting for input.
    Checks deduplication state to avoid double-notifications.
    """

    def __init__(self, config=None):
        super().__init__(config)
        self._use_input_settings = False

    @property
    def hook_config(self) -> StopHookConfig:
        """Get stop-specific hook configuration."""
        return self.config.stop

    def should_handle(self, data: dict) -> bool:  # noqa: ARG002
        """Check if this handler should process the stop event."""
        return self.hook_config.enabled

    def get_audio_settings(self) -> AudioSettings:
        """Get audio settings for task completion."""
        return AudioSettings(
            sound=self.hook_config.sound,
            voice=self.hook_config.voice,
        )

    def _get_input_audio_settings(self) -> AudioSettings:
        """Get audio settings for input waiting notification."""
        # Use AskUserQuestion settings for input waiting
        ask_config = self.config.ask_user_question
        return AudioSettings(
            sound=ask_config.sound,
            voice=ask_config.voice,
        )

    def _detect_input_waiting(self, message_info: MessageInfo) -> tuple[bool, str | None]:
        """Detect if Claude is waiting for user input.

        Args:
            message_info: Parsed message info from transcript

        Returns:
            Tuple of (is_waiting, question_text)
        """
        ask_config = self.config.ask_user_question

        # Priority 1: Check for AskUserQuestion tool (most explicit)
        ask_input = message_info.ask_user_question_input
        if ask_input:
            questions = ask_input.get("questions", [])
            if questions:
                first_q = questions[0].get("question", "")
                return True, first_q or ask_config.default_message
            return True, ask_config.default_message

        # Priority 2: Check if text ends with question mark
        # Signal input-waiting for audio settings, but let get_message()
        # decide whether to speak the summary or the question.
        text = message_info.text or ""
        if text.strip().endswith("?"):
            return True, None

        # Priority 3: Check if message ends with tool_use (waiting for permission)
        if message_info.ends_with_tool_use:
            tool_name = message_info.last_tool_name or "tool"
            perm_config = self.config.permission_request
            return True, perm_config.message_template.format(tool_name=tool_name)

        return False, None

    def _check_deduplication(self, data: dict) -> bool:
        """Check if this event was already handled by another hook.

        Args:
            data: Hook data

        Returns:
            True if already handled and should skip
        """
        session_id = data.get("session_id", "")
        if not session_id:
            return False

        # Check if AskUserQuestion was already handled
        if was_handled(session_id, "ask_user"):
            self.log("dedup: ask_user already handled - skipping")
            return True

        # Check if PermissionRequest was already handled
        if was_handled(session_id, "permission"):
            self.log("dedup: permission already handled - skipping")
            return True

        # Check if Notification (idle_prompt) was already handled
        if was_handled(session_id, "notification_idle"):
            self.log("dedup: notification_idle already handled - skipping")
            return True

        # Check if PostToolUseFailure was already handled
        if was_handled(session_id, "tool_failure"):
            self.log("dedup: tool_failure already handled - skipping")
            return True

        return False

    def get_message(self, data: dict) -> str | None:
        """Extract message from stop event data."""
        # Get transcript path
        transcript_path, fallback_used = get_transcript_path(
            data, self.project_dir, wait_timeout=2.0
        )
        self.log(f"transcript_path: {transcript_path}")
        self.log(f"fallback_used: {fallback_used}")

        if not transcript_path:
            self.log("No transcript found")
            return None

        # Copy transcript for debugging
        if self.debug_enabled and transcript_path:
            try:
                dump_path = self.debug_dir / "transcript_dump.jsonl"
                dump_path.parent.mkdir(parents=True, exist_ok=True)
                with open(transcript_path) as src:
                    with open(dump_path, "w") as dst:
                        dst.write(src.read())
            except (IOError, OSError):
                pass

        # Save raw input for debugging
        if self.debug_enabled:
            try:
                input_path = self.debug_dir / "hook_raw_input.json"
                with open(input_path, "w") as f:
                    json.dump(data, f, indent=2)
            except (IOError, OSError):
                pass

        # Read transcript
        message_info = read_transcript(transcript_path)
        if not message_info:
            self.log("No message info from transcript")
            return None

        self.log(f"text_preview: {(message_info.text or '')[:100]}...")
        self.log(f"tool_names: {message_info.tool_names}")
        self.log(f"ends_with_tool_use: {message_info.ends_with_tool_use}")
        self.log(f"has_ask_user_question: {message_info.ask_user_question_input is not None}")

        # Check if waiting for input
        is_waiting, question = self._detect_input_waiting(message_info)

        if is_waiting:
            self.log("input_waiting: True")
            self.log(f"question: {question}")
            # Only check dedup for input-waiting notifications — these are the
            # genuine duplicates when PermissionRequest or AskUserQuestion already
            # spoke the same prompt. Task-completion summaries are never duplicates.
            if self._check_deduplication(data):
                # Dedup suppressed the input-waiting notification (permission/question
                # already handled). But this is still a Stop event — if there's
                # meaningful text from earlier in the turn, speak the summary instead
                # of going silent. Use read_last_assistant_text to find text from an
                # earlier assistant message (the last one may be tool-only).
                self.log("dedup: falling through to summary extraction")
                text = read_last_assistant_text(transcript_path)
                if text:
                    message_info = MessageInfo(text=text)
                else:
                    self.log("dedup: no text found in transcript")
                    return None
            else:
                # Override audio settings and sound for input notification
                self._use_input_settings = True
                if question is not None:
                    # AskUserQuestion or ends-with-tool-use — speak the specific prompt
                    return question
                # Text ends with ? — fall through to extract action summary below.
                # If no action summary found, extract_last_question as fallback.

        if not is_waiting:
            # Normal task completion
            self._use_input_settings = False

        if not message_info.text:
            self.log("No text content")
            return None

        # Build summary config from hook settings
        summary_cfg = self.hook_config.summary
        config = SummaryConfig(
            mode=summary_cfg.mode,
            max_sentences=summary_cfg.max_sentences,
            max_characters=summary_cfg.max_characters,
            start=summary_cfg.start,
        )

        summary = extract_summary(message_info.text, config)
        self.log(f"summary: {summary}")

        if summary and summary != "Task completed":
            return summary

        # If input-waiting (text ended with ?) and no action summary, speak the question
        if self._use_input_settings:
            question = extract_last_question(message_info.text)
            if question:
                return question
            return self.config.ask_user_question.default_message

        return summary

    def _resolve_audio_settings(self, data: dict) -> AudioSettings:
        """Use input-waiting settings when Claude is waiting for user input."""
        if self._use_input_settings:
            return self._get_input_audio_settings()
        return self.get_audio_settings()
