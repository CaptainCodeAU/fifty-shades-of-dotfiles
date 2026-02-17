"""Notification hook handler for system notification events."""

from ..audio import AudioSettings
from ..config import NotificationHookConfig
from ..state import mark_handled
from .base import BaseHandler


class NotificationHandler(BaseHandler):
    """Handler for the Notification hook event.

    Notifies when Claude sends system notifications like idle prompts
    or auth success events.
    """

    @property
    def hook_config(self) -> NotificationHookConfig:
        """Get notification-specific hook configuration."""
        return self.config.notification

    def should_handle(self, data: dict) -> bool:  # noqa: ARG002
        """Check if this handler should process the event."""
        return self.hook_config.enabled

    def get_audio_settings(self) -> AudioSettings:
        """Get audio settings for notification."""
        return AudioSettings(
            sound=self.hook_config.sound,
            voice=self.hook_config.voice,
        )

    def get_message(self, data: dict) -> str | None:
        """Map notification type to configured message."""
        notification_type = data.get("notification_type", "")
        cfg = self.hook_config

        messages = {
            "idle_prompt": cfg.idle_message,
            "auth_success": cfg.auth_message,
        }

        return messages.get(notification_type, cfg.default_message)

    def _pre_message_hook(self, data: dict) -> None:
        """Mark idle notifications as handled for Stop dedup."""
        session_id = data.get("session_id", "")
        notification_type = data.get("notification_type", "")
        if session_id and notification_type == "idle_prompt":
            mark_handled(session_id, "notification_idle")
            self.log(f"marked_handled: notification_idle for session {session_id}")
