#!/usr/bin/env python
# /// script
# requires-python = ">=3.11"
# dependencies = ["pytest"]
# ///
"""Tests for dedup state management."""

import json
import time
from pathlib import Path
from unittest.mock import patch

import pytest

from lib.state import (
    STATE_EXPIRY_SECONDS,
    cleanup_stale_states,
    clear_state,
    mark_handled,
    set_last_spoken,
    was_already_spoken,
    was_handled,
)


@pytest.fixture
def state_dir(tmp_path):
    """Provide a temporary state directory."""
    d = tmp_path / "hook-state"
    d.mkdir()
    return str(d)


class TestMarkAndWasHandled:
    def test_roundtrip(self, state_dir):
        mark_handled("sess1", "ask_user", state_dir=state_dir)
        assert was_handled("sess1", "ask_user", state_dir=state_dir)

    def test_unhandled_event(self, state_dir):
        mark_handled("sess1", "ask_user", state_dir=state_dir)
        assert not was_handled("sess1", "permission", state_dir=state_dir)

    def test_multiple_events(self, state_dir):
        mark_handled("sess1", "ask_user", state_dir=state_dir)
        mark_handled("sess1", "permission", state_dir=state_dir)
        assert was_handled("sess1", "ask_user", state_dir=state_dir)
        assert was_handled("sess1", "permission", state_dir=state_dir)

    def test_idempotent_mark(self, state_dir):
        mark_handled("sess1", "ask_user", state_dir=state_dir)
        mark_handled("sess1", "ask_user", state_dir=state_dir)
        assert was_handled("sess1", "ask_user", state_dir=state_dir)

    def test_session_isolation(self, state_dir):
        mark_handled("sess1", "ask_user", state_dir=state_dir)
        assert not was_handled("sess2", "ask_user", state_dir=state_dir)

    def test_expiry(self, state_dir):
        mark_handled("sess1", "ask_user", state_dir=state_dir)
        # Advance time past expiry
        with patch("lib.state.time") as mock_time:
            mock_time.time.return_value = time.time() + STATE_EXPIRY_SECONDS + 1
            assert not was_handled("sess1", "ask_user", state_dir=state_dir)


class TestLastSpoken:
    def test_roundtrip(self, state_dir):
        set_last_spoken("sess1", "Hello world", state_dir=state_dir)
        assert was_already_spoken("sess1", "Hello world", state_dir=state_dir)

    def test_different_message(self, state_dir):
        set_last_spoken("sess1", "Hello world", state_dir=state_dir)
        assert not was_already_spoken("sess1", "Goodbye world", state_dir=state_dir)

    def test_no_prior_spoken(self, state_dir):
        assert not was_already_spoken("sess1", "anything", state_dir=state_dir)

    def test_session_isolation(self, state_dir):
        set_last_spoken("sess1", "Hello", state_dir=state_dir)
        assert not was_already_spoken("sess2", "Hello", state_dir=state_dir)


class TestClearState:
    def test_clears_handled(self, state_dir):
        mark_handled("sess1", "ask_user", state_dir=state_dir)
        clear_state("sess1", state_dir=state_dir)
        assert not was_handled("sess1", "ask_user", state_dir=state_dir)

    def test_clear_nonexistent(self, state_dir):
        # Should not raise
        clear_state("nonexistent", state_dir=state_dir)


class TestCorruptedState:
    def test_malformed_json(self, state_dir):
        # Write garbage to state file
        state_file = Path(state_dir) / ".hook_state_sess1.json"
        state_file.write_text("not json{{{")
        # Should return False, not raise
        assert not was_handled("sess1", "ask_user", state_dir=state_dir)

    def test_missing_directory(self, tmp_path):
        nonexistent = str(tmp_path / "does" / "not" / "exist")
        # was_handled should return False (no state file)
        assert not was_handled("sess1", "ask_user", state_dir=nonexistent)
        # mark_handled should create the directory
        mark_handled("sess1", "ask_user", state_dir=nonexistent)
        assert was_handled("sess1", "ask_user", state_dir=nonexistent)


class TestCleanupStaleStates:
    def test_removes_expired(self, state_dir):
        mark_handled("sess1", "ask_user", state_dir=state_dir)
        # Manually backdate the timestamp
        state_file = Path(state_dir) / ".hook_state_sess1.json"
        data = json.loads(state_file.read_text())
        data["timestamp"] = time.time() - STATE_EXPIRY_SECONDS - 10
        state_file.write_text(json.dumps(data))

        cleanup_stale_states(state_dir=state_dir)
        assert not state_file.exists()

    def test_keeps_fresh(self, state_dir):
        mark_handled("sess1", "ask_user", state_dir=state_dir)
        cleanup_stale_states(state_dir=state_dir)
        assert was_handled("sess1", "ask_user", state_dir=state_dir)

    def test_removes_corrupted(self, state_dir):
        state_file = Path(state_dir) / ".hook_state_bad.json"
        state_file.write_text("corrupted{{{")
        cleanup_stale_states(state_dir=state_dir)
        assert not state_file.exists()

    def test_nonexistent_dir(self, tmp_path):
        nonexistent = str(tmp_path / "nope")
        # Should not raise
        cleanup_stale_states(state_dir=nonexistent)
