"""Deduplication state management for Claude Code hooks."""

import hashlib
import json
import time
from pathlib import Path


# State file expiry in seconds (prevents stale state across sessions)
STATE_EXPIRY_SECONDS = 60

# System temp directory for state files (outside project directory)
STATE_DIR = "/tmp/claude-hooks"


def _get_state_file_path(session_id: str, state_dir: str | None = None) -> Path:
    """Get the path to the state file for a session.

    Args:
        session_id: Unique session identifier
        state_dir: Directory to store state files (defaults to STATE_DIR)

    Returns:
        Path to the state file
    """
    directory = state_dir if state_dir is not None else STATE_DIR
    # Sanitize session_id for filename
    safe_id = session_id.replace("/", "_").replace("\\", "_")
    return Path(directory) / f".hook_state_{safe_id}.json"


def _load_state(state_path: Path) -> dict:
    """Load state from file, returning empty dict if not found or expired.

    Args:
        state_path: Path to state file

    Returns:
        State dictionary
    """
    if not state_path.exists():
        return {}

    try:
        with open(state_path) as f:
            state = json.load(f)

        # Check expiry
        timestamp = state.get("timestamp", 0)
        if time.time() - timestamp > STATE_EXPIRY_SECONDS:
            # State expired, clean up
            state_path.unlink(missing_ok=True)
            return {}

        return state
    except (json.JSONDecodeError, IOError, OSError):
        return {}


def _save_state(state_path: Path, state: dict) -> None:
    """Save state to file.

    Args:
        state_path: Path to state file
        state: State dictionary to save
    """
    # Ensure directory exists
    state_path.parent.mkdir(parents=True, exist_ok=True)

    # Update timestamp
    state["timestamp"] = time.time()

    try:
        with open(state_path, "w") as f:
            json.dump(state, f)
    except (IOError, OSError):
        pass  # Silently fail on write errors


def mark_handled(session_id: str, event_type: str, state_dir: str | None = None) -> None:
    """Mark an event as handled for deduplication.

    Args:
        session_id: Unique session identifier
        event_type: Type of event (e.g., "ask_user", "permission")
        state_dir: Directory to store state files (defaults to STATE_DIR)
    """
    state_path = _get_state_file_path(session_id, state_dir)
    state = _load_state(state_path)

    handled = state.get("handled", [])
    if event_type not in handled:
        handled.append(event_type)
    state["handled"] = handled

    _save_state(state_path, state)


def was_handled(session_id: str, event_type: str, state_dir: str | None = None) -> bool:
    """Check if an event was already handled.

    Args:
        session_id: Unique session identifier
        event_type: Type of event to check
        state_dir: Directory where state files are stored (defaults to STATE_DIR)

    Returns:
        True if event was already handled
    """
    state_path = _get_state_file_path(session_id, state_dir)
    state = _load_state(state_path)

    handled = state.get("handled", [])
    return event_type in handled


def clear_state(session_id: str, state_dir: str | None = None) -> None:
    """Clear state for a session.

    Args:
        session_id: Unique session identifier
        state_dir: Directory where state files are stored (defaults to STATE_DIR)
    """
    state_path = _get_state_file_path(session_id, state_dir)
    try:
        state_path.unlink(missing_ok=True)
    except (IOError, OSError):
        pass


def set_last_spoken(session_id: str, message: str, state_dir: str | None = None) -> None:
    """Store a hash of the last spoken message.

    Args:
        session_id: Unique session identifier
        message: The message that was spoken
        state_dir: Directory to store state files (defaults to STATE_DIR)
    """
    state_path = _get_state_file_path(session_id, state_dir)
    state = _load_state(state_path)
    state["last_spoken_hash"] = hashlib.md5(message.encode()).hexdigest()
    _save_state(state_path, state)


def was_already_spoken(session_id: str, message: str, state_dir: str | None = None) -> bool:
    """Check if this message was the last one spoken.

    Args:
        session_id: Unique session identifier
        message: The message to check
        state_dir: Directory where state files are stored (defaults to STATE_DIR)

    Returns:
        True if this message was the last one spoken
    """
    state_path = _get_state_file_path(session_id, state_dir)
    state = _load_state(state_path)
    stored = state.get("last_spoken_hash")
    if not stored:
        return False
    return stored == hashlib.md5(message.encode()).hexdigest()


def cleanup_stale_states(state_dir: str | None = None) -> None:
    """Remove all expired state files.

    Args:
        state_dir: Directory where state files are stored (defaults to STATE_DIR)
    """
    state_dir_path = Path(state_dir if state_dir is not None else STATE_DIR)
    if not state_dir_path.exists():
        return

    current_time = time.time()

    for state_file in state_dir_path.glob(".hook_state_*.json"):
        try:
            with open(state_file) as f:
                state = json.load(f)
            timestamp = state.get("timestamp", 0)
            if current_time - timestamp > STATE_EXPIRY_SECONDS:
                state_file.unlink(missing_ok=True)
        except (json.JSONDecodeError, IOError, OSError):
            # Remove corrupted files
            try:
                state_file.unlink(missing_ok=True)
            except (IOError, OSError):
                pass
