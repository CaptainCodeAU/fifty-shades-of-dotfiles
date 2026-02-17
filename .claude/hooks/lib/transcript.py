"""Transcript parsing utilities for Claude Code hooks."""

import json
import os
import time
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class MessageInfo:
    """Information extracted from an assistant message."""

    text: str | None = None
    tool_names: list[str] = field(default_factory=list)
    ends_with_tool_use: bool = False
    last_tool_name: str | None = None
    ask_user_question_input: dict | None = None


def wait_for_file(path: str | Path, timeout: float = 2.0, interval: float = 0.1) -> bool:
    """Wait for a file to exist, with timeout.

    Args:
        path: Path to file
        timeout: Maximum wait time in seconds
        interval: Check interval in seconds

    Returns:
        True if file exists, False if timeout
    """
    if not path:
        return False

    elapsed = 0.0
    while elapsed < timeout:
        if os.path.exists(path):
            return True
        time.sleep(interval)
        elapsed += interval
    return False


def find_recent_transcript(project_dir: str) -> str | None:
    """Find the most recent transcript file for a project.

    Args:
        project_dir: Path to the project directory

    Returns:
        Path to most recent transcript file, or None if not found
    """
    if not project_dir:
        return None

    # The project path gets encoded with dashes replacing slashes
    project_path_encoded = project_dir.replace("/", "-")
    claude_projects_dir = os.path.expanduser("~/.claude/projects")

    if not os.path.exists(claude_projects_dir):
        return None

    matching_dirs = []
    for name in os.listdir(claude_projects_dir):
        if project_path_encoded in name or name == project_path_encoded:
            full_path = os.path.join(claude_projects_dir, name)
            if os.path.isdir(full_path):
                matching_dirs.append(full_path)

    # Find the most recent .jsonl file across all matching directories
    newest_file = None
    newest_mtime = 0.0

    for dir_path in matching_dirs:
        try:
            for filename in os.listdir(dir_path):
                if filename.endswith(".jsonl"):
                    file_path = os.path.join(dir_path, filename)
                    mtime = os.path.getmtime(file_path)
                    if mtime > newest_mtime:
                        newest_mtime = mtime
                        newest_file = file_path
        except (IOError, OSError):
            continue

    return newest_file


def read_transcript(transcript_path: str | Path | None) -> MessageInfo | None:
    """Read JSONL transcript and return the last assistant message info.

    Args:
        transcript_path: Path to the transcript JSONL file

    Returns:
        MessageInfo with extracted data, or None if not found
    """
    if not transcript_path or not os.path.exists(transcript_path):
        return None

    last_info: MessageInfo | None = None

    try:
        with open(transcript_path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                    if entry.get("type") == "assistant":
                        message = entry.get("message", {})
                        content = message.get("content", [])

                        info = MessageInfo()
                        text_parts: list[str] = []
                        last_block_type: str | None = None

                        for block in content:
                            if isinstance(block, dict):
                                block_type = block.get("type")
                                last_block_type = block_type

                                if block_type == "text":
                                    text_parts.append(block.get("text", ""))
                                elif block_type == "tool_use":
                                    tool_name = block.get("name", "")
                                    info.tool_names.append(tool_name)
                                    info.last_tool_name = tool_name

                                    if tool_name == "AskUserQuestion":
                                        info.ask_user_question_input = block.get("input", {})
                            elif isinstance(block, str):
                                text_parts.append(block)
                                last_block_type = "text"

                        if text_parts:
                            info.text = " ".join(text_parts)
                        info.ends_with_tool_use = last_block_type == "tool_use"

                        last_info = info
                except json.JSONDecodeError:
                    continue
    except (IOError, OSError):
        return None

    return last_info


def read_last_assistant_text(transcript_path: str | Path | None) -> str | None:
    """Read JSONL transcript and return text from the last assistant message that has text.

    Unlike read_transcript() which returns the very last assistant message (which may
    be a tool-only message with no prose), this scans backward to find the most recent
    assistant message that contains actual text content.

    Args:
        transcript_path: Path to the transcript JSONL file

    Returns:
        The text content, or None if no assistant message with text was found
    """
    if not transcript_path or not os.path.exists(transcript_path):
        return None

    last_text: str | None = None

    try:
        with open(transcript_path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                    if entry.get("type") == "assistant":
                        content = entry.get("message", {}).get("content", [])
                        text_parts: list[str] = []

                        for block in content:
                            if isinstance(block, dict) and block.get("type") == "text":
                                text_parts.append(block.get("text", ""))
                            elif isinstance(block, str):
                                text_parts.append(block)

                        if text_parts:
                            last_text = " ".join(text_parts)
                except json.JSONDecodeError:
                    continue
    except (IOError, OSError):
        return None

    return last_text


def get_transcript_path(
    hook_data: dict,
    project_dir: str,
    wait_timeout: float = 2.0,
) -> tuple[str | None, bool]:
    """Get transcript path from hook data with fallback.

    Args:
        hook_data: Data from the hook stdin
        project_dir: Project directory for fallback search
        wait_timeout: How long to wait for file if not immediately available

    Returns:
        Tuple of (path, used_fallback)
    """
    transcript_path = hook_data.get("transcript_path")

    # Try the provided path first
    if transcript_path:
        if os.path.exists(transcript_path):
            return transcript_path, False
        # Wait for file to appear (race condition handling)
        if wait_for_file(transcript_path, timeout=wait_timeout):
            return transcript_path, False

    # Fallback to searching for recent transcripts
    fallback_path = find_recent_transcript(project_dir)
    if fallback_path:
        return fallback_path, True

    return None, False
