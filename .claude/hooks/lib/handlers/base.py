"""Base handler class for Claude Code hooks."""

from abc import ABC, abstractmethod
from pathlib import Path

from ..audio import AudioSettings, play_notification
from ..config import Config, get_config


class BaseHandler(ABC):
    """Abstract base class for hook handlers."""

    def __init__(self, config: Config | None = None):
        """Initialize the handler.

        Args:
            config: Configuration object. If None, loads from default location.
        """
        self.config = config or get_config()
        self._debug_log: list[str] = []

    @property
    def project_dir(self) -> str:
        """Get the project directory from config."""
        return self.config.global_config.project_dir

    @property
    def debug_enabled(self) -> bool:
        """Check if debug mode is enabled."""
        return self.config.global_config.debug

    @property
    def debug_dir(self) -> Path:
        """Get the debug output directory."""
        return Path(self.project_dir) / self.config.global_config.debug_dir

    def log(self, message: str) -> None:
        """Add a message to the debug log.

        Args:
            message: Message to log
        """
        self._debug_log.append(message)

    def write_debug_log(self, filename: str = "hook_debug.log") -> None:
        """Write debug log to file if debug is enabled.

        Args:
            filename: Name of the debug log file
        """
        if not self.debug_enabled:
            return

        debug_path = self.debug_dir / filename
        debug_path.parent.mkdir(parents=True, exist_ok=True)

        try:
            with open(debug_path, "w") as f:
                f.write("\n".join(self._debug_log))
        except (IOError, OSError):
            pass

    @abstractmethod
    def should_handle(self, data: dict) -> bool:
        """Determine if this handler should process the hook data.

        Args:
            data: Hook data from stdin

        Returns:
            True if this handler should process the data
        """
        ...

    @abstractmethod
    def get_message(self, data: dict) -> str | None:
        """Extract the message to speak from hook data.

        Args:
            data: Hook data from stdin

        Returns:
            Message to speak, or None to skip notification
        """
        ...

    @abstractmethod
    def get_audio_settings(self) -> AudioSettings:
        """Get audio settings for this handler.

        Returns:
            AudioSettings for notification
        """
        ...

    def _pre_message_hook(self, data: dict) -> None:
        """Called after should_handle passes, before get_message. No-op by default."""
        pass

    def _resolve_audio_settings(self, data: dict) -> AudioSettings:
        """Resolve audio settings. Default delegates to get_audio_settings()."""
        return self.get_audio_settings()

    def handle(self, data: dict) -> None:
        """Main entry point for handling hook events.

        Args:
            data: Hook data from stdin
        """
        self.log(f"Handler: {self.__class__.__name__}")
        self.log(f"hook_event_name: {data.get('hook_event_name', 'unknown')}")
        tool_name = data.get("tool_name")
        if tool_name:
            self.log(f"tool_name: {tool_name}")

        if not self.should_handle(data):
            self.log("should_handle: False - skipping")
            self.write_debug_log()
            return

        self.log("should_handle: True")

        self._pre_message_hook(data)

        message = self.get_message(data)
        if not message:
            self.log("message: None - skipping notification")
            self.write_debug_log()
            return

        self.log(f"message: {message}")

        settings = self._resolve_audio_settings(data)

        play_notification(
            message=message,
            settings=settings,
            project_dir=self.project_dir,
        )

        self.log("notification: played")
        self.write_debug_log()
