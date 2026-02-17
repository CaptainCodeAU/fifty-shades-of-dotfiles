"""Configuration loading and validation for Claude Code hooks."""

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml


@dataclass
class SoundConfig:
    """Sound effect settings."""

    enabled: bool = True
    file: str = ""
    volume: float = 0.5
    delay_ms: int = 200


@dataclass
class VoiceConfig:
    """Voice/speech settings."""

    enabled: bool = True
    name: str = "Victoria"
    volume: float = 0.6
    rate: int = 280


@dataclass
class SummaryConfig:
    """Summary extraction settings."""

    mode: str = "sentences"  # "sentences" or "characters"
    max_sentences: int = 2
    max_characters: int = 200
    start: str = "action"  # "action" or "beginning"


@dataclass
class HookConfig:
    """Base configuration for a hook."""

    enabled: bool = True
    sound: SoundConfig = field(default_factory=SoundConfig)
    voice: VoiceConfig = field(default_factory=VoiceConfig)


@dataclass
class StopHookConfig(HookConfig):
    """Configuration for Stop hook."""

    summary: SummaryConfig = field(default_factory=SummaryConfig)


@dataclass
class AskUserQuestionHookConfig(HookConfig):
    """Configuration for AskUserQuestion hook."""

    message_mode: str = "extract"  # "extract" or "generic"
    default_message: str = "Claude has a question for you"


@dataclass
class PermissionRequestHookConfig(HookConfig):
    """Configuration for PermissionRequest hook."""

    message_template: str = "Approve {tool_name}?"


@dataclass
class NotificationHookConfig(HookConfig):
    """Configuration for Notification hook."""

    idle_message: str = "Claude is idle"
    auth_message: str = "Auth successful"
    default_message: str = "Notification"


@dataclass
class SubagentStartHookConfig(HookConfig):
    """Configuration for SubagentStart hook."""

    message_template: str = "Subagent {agent_type} started"


@dataclass
class SubagentStopHookConfig(HookConfig):
    """Configuration for SubagentStop hook."""

    message_template: str = "Subagent {agent_type} finished"


@dataclass
class TeammateIdleHookConfig(HookConfig):
    """Configuration for TeammateIdle hook."""

    message_template: str = "{teammate_name} is idle"


@dataclass
class TaskCompletedHookConfig(HookConfig):
    """Configuration for TaskCompleted hook."""

    message_template: str = "Task completed: {task_subject}"
    max_subject_length: int = 80


@dataclass
class PostToolUseFailureHookConfig(HookConfig):
    """Configuration for PostToolUseFailure hook."""

    message_template: str = "{tool_name} failed"


@dataclass
class UserPromptSubmitHookConfig(HookConfig):
    """Configuration for UserPromptSubmit hook (disabled by default)."""

    enabled: bool = False


@dataclass
class PreCompactHookConfig(HookConfig):
    """Configuration for PreCompact hook."""

    message: str = "Compacting context"


@dataclass
class GlobalConfig:
    """Global configuration settings."""

    debug: bool = True
    debug_dir: str = "Temp"
    project_dir: str = ""


@dataclass
class Config:
    """Complete hook configuration."""

    global_config: GlobalConfig = field(default_factory=GlobalConfig)
    stop: StopHookConfig = field(default_factory=StopHookConfig)
    ask_user_question: AskUserQuestionHookConfig = field(
        default_factory=AskUserQuestionHookConfig
    )
    permission_request: PermissionRequestHookConfig = field(
        default_factory=PermissionRequestHookConfig
    )
    notification: NotificationHookConfig = field(default_factory=NotificationHookConfig)
    subagent_start: SubagentStartHookConfig = field(default_factory=SubagentStartHookConfig)
    subagent_stop: SubagentStopHookConfig = field(default_factory=SubagentStopHookConfig)
    teammate_idle: TeammateIdleHookConfig = field(default_factory=TeammateIdleHookConfig)
    task_completed: TaskCompletedHookConfig = field(default_factory=TaskCompletedHookConfig)
    post_tool_use_failure: PostToolUseFailureHookConfig = field(
        default_factory=PostToolUseFailureHookConfig
    )
    user_prompt_submit: UserPromptSubmitHookConfig = field(
        default_factory=UserPromptSubmitHookConfig
    )
    pre_compact: PreCompactHookConfig = field(default_factory=PreCompactHookConfig)


# Cached config instance
_config: Config | None = None
_config_path: Path | None = None


def _dict_to_dataclass(data: dict[str, Any], cls: type) -> Any:
    """Convert a dictionary to a dataclass, handling nested types."""
    if not isinstance(data, dict):
        return data

    field_types = {f.name: f.type for f in cls.__dataclass_fields__.values()}
    kwargs = {}

    for key, value in data.items():
        if key in field_types:
            field_type = field_types[key]
            # Handle nested dataclasses
            if hasattr(field_type, "__dataclass_fields__"):
                kwargs[key] = _dict_to_dataclass(value, field_type)
            else:
                kwargs[key] = value

    return cls(**kwargs)


def _load_hook_config(hook_data: dict[str, Any], cls: type) -> Any:
    """Load a hook config with nested sound and voice configs.

    Args:
        hook_data: Raw hook data from YAML
        cls: The hook config class to instantiate

    Returns:
        Populated hook config instance
    """
    data = hook_data.copy()

    # Handle nested sound config
    if "sound" in data:
        data["sound"] = _dict_to_dataclass(data["sound"], SoundConfig)

    # Handle nested voice config
    if "voice" in data:
        data["voice"] = _dict_to_dataclass(data["voice"], VoiceConfig)

    # Handle nested summary config (for StopHookConfig)
    if "summary" in data:
        data["summary"] = _dict_to_dataclass(data["summary"], SummaryConfig)

    return _dict_to_dataclass(data, cls)


def load_config(config_path: str | Path | None = None, force_reload: bool = False) -> Config:
    """Load configuration from YAML file.

    Args:
        config_path: Path to config.yaml. If None, uses default location.
        force_reload: If True, ignore cached config and reload from disk.

    Returns:
        Config object with all settings.
    """
    global _config, _config_path

    if config_path is None:
        # Default to config.yaml in the same directory as this file
        config_path = Path(__file__).parent.parent / "config.yaml"
    else:
        config_path = Path(config_path)

    # Return cached config if available and path matches
    if not force_reload and _config is not None and _config_path == config_path:
        return _config

    # Load YAML file
    if not config_path.exists():
        # Return default config if file doesn't exist
        _config = Config()
        _config_path = config_path
        return _config

    with open(config_path) as f:
        data = yaml.safe_load(f) or {}

    # Build config from loaded data
    config = Config()

    # Global settings
    if "global" in data:
        config.global_config = _dict_to_dataclass(data["global"], GlobalConfig)

    # Hook-specific settings
    hooks = data.get("hooks", {})

    if "stop" in hooks:
        config.stop = _load_hook_config(hooks["stop"], StopHookConfig)

    if "ask_user_question" in hooks:
        config.ask_user_question = _load_hook_config(
            hooks["ask_user_question"], AskUserQuestionHookConfig
        )

    if "permission_request" in hooks:
        config.permission_request = _load_hook_config(
            hooks["permission_request"], PermissionRequestHookConfig
        )

    if "notification" in hooks:
        config.notification = _load_hook_config(hooks["notification"], NotificationHookConfig)

    if "subagent_start" in hooks:
        config.subagent_start = _load_hook_config(
            hooks["subagent_start"], SubagentStartHookConfig
        )

    if "subagent_stop" in hooks:
        config.subagent_stop = _load_hook_config(hooks["subagent_stop"], SubagentStopHookConfig)

    if "teammate_idle" in hooks:
        config.teammate_idle = _load_hook_config(
            hooks["teammate_idle"], TeammateIdleHookConfig
        )

    if "task_completed" in hooks:
        config.task_completed = _load_hook_config(
            hooks["task_completed"], TaskCompletedHookConfig
        )

    if "post_tool_use_failure" in hooks:
        config.post_tool_use_failure = _load_hook_config(
            hooks["post_tool_use_failure"], PostToolUseFailureHookConfig
        )

    if "user_prompt_submit" in hooks:
        config.user_prompt_submit = _load_hook_config(
            hooks["user_prompt_submit"], UserPromptSubmitHookConfig
        )

    if "pre_compact" in hooks:
        config.pre_compact = _load_hook_config(hooks["pre_compact"], PreCompactHookConfig)

    # Apply environment variable overrides
    if os.environ.get("HOOK_DEBUG"):
        config.global_config.debug = os.environ["HOOK_DEBUG"].lower() in ("1", "true", "yes")

    if os.environ.get("HOOK_PROJECT_DIR"):
        config.global_config.project_dir = os.environ["HOOK_PROJECT_DIR"]

    # Fall back to CWD (Claude Code sets this to the project root)
    if not config.global_config.project_dir:
        config.global_config.project_dir = os.getcwd()

    # Cache and return
    _config = config
    _config_path = config_path
    return config


def get_config() -> Config:
    """Get the current configuration, loading if necessary."""
    if _config is None:
        return load_config()
    return _config
