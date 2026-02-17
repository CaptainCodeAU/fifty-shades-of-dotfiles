#!/usr/bin/env python
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml"]
# ///
"""
Claude Code Hook Runner - Unified entrypoint for all hook events.

This script reads JSON from stdin, auto-detects the hook event type,
loads configuration, and routes to the appropriate handler.
"""

import json
import sys
from pathlib import Path

# Add lib to path for imports
lib_path = Path(__file__).parent / "lib"
sys.path.insert(0, str(lib_path.parent))

from lib.config import load_config
from lib.handlers import (
    AskUserQuestionHandler,
    NotificationHandler,
    PermissionRequestHandler,
    PostToolUseFailureHandler,
    PreCompactHandler,
    StopHandler,
    SubagentStartHandler,
    SubagentStopHandler,
    TaskCompletedHandler,
    TeammateIdleHandler,
    UserPromptSubmitHandler,
)


def main():
    """Main entry point for hook processing."""
    # Read raw stdin
    try:
        raw_input = sys.stdin.read()
        data = json.loads(raw_input) if raw_input else {}
    except json.JSONDecodeError:
        data = {}

    # Load configuration
    config_path = Path(__file__).parent / "config.yaml"
    config = load_config(config_path)

    # Detect hook event type
    hook_event = data.get("hook_event_name", "")

    # Route to appropriate handler
    handler = None

    if hook_event == "Stop":
        handler = StopHandler(config)
    elif hook_event == "PostToolUse":
        # Check if this is an AskUserQuestion tool
        tool_name = data.get("tool_name", "")
        if tool_name == "AskUserQuestion":
            handler = AskUserQuestionHandler(config)
    elif hook_event == "PermissionRequest":
        handler = PermissionRequestHandler(config)
    elif hook_event == "PostToolUseFailure":
        handler = PostToolUseFailureHandler(config)
    elif hook_event == "Notification":
        handler = NotificationHandler(config)
    elif hook_event == "SubagentStart":
        handler = SubagentStartHandler(config)
    elif hook_event == "SubagentStop":
        handler = SubagentStopHandler(config)
    elif hook_event == "TeammateIdle":
        handler = TeammateIdleHandler(config)
    elif hook_event == "TaskCompleted":
        handler = TaskCompletedHandler(config)
    elif hook_event == "UserPromptSubmit":
        handler = UserPromptSubmitHandler(config)
    elif hook_event == "PreCompact":
        handler = PreCompactHandler(config)

    # Handle the event
    if handler:
        try:
            handler.handle(data)
        except Exception as e:
            # Log error but don't crash the hook
            if config.global_config.debug:
                debug_dir = Path(config.global_config.project_dir) / config.global_config.debug_dir
                debug_dir.mkdir(parents=True, exist_ok=True)
                error_log = debug_dir / "hook_error.log"
                with open(error_log, "w") as f:
                    f.write(f"Error in {handler.__class__.__name__}: {e}\n")
                    import traceback
                    f.write(traceback.format_exc())


if __name__ == "__main__":
    main()
