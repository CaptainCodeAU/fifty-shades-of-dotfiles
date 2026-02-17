"""TaskCompleted hook handler for task completion notifications."""

from ..audio import AudioSettings
from ..config import TaskCompletedHookConfig
from .base import BaseHandler


class TaskCompletedHandler(BaseHandler):
    """Handler for the TaskCompleted hook event.

    Notifies when a task is completed.
    """

    @property
    def hook_config(self) -> TaskCompletedHookConfig:
        """Get task_completed-specific hook configuration."""
        return self.config.task_completed

    def should_handle(self, data: dict) -> bool:  # noqa: ARG002
        """Check if this handler should process the event."""
        return self.hook_config.enabled

    def get_audio_settings(self) -> AudioSettings:
        """Get audio settings for task completed notification."""
        return AudioSettings(
            sound=self.hook_config.sound,
            voice=self.hook_config.voice,
        )

    def get_message(self, data: dict) -> str | None:
        """Format task completed message, truncating subject to max length."""
        task_subject = data.get("task_subject", "unknown task")
        max_len = self.hook_config.max_subject_length
        if len(task_subject) > max_len:
            task_subject = task_subject[:max_len - 3] + "..."
        return self.hook_config.message_template.format(task_subject=task_subject)
