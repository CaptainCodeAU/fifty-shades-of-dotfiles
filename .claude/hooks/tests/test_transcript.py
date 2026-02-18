#!/usr/bin/env python
# /// script
# requires-python = ">=3.11"
# dependencies = ["pytest"]
# ///
"""Tests for transcript JSONL parsing."""

import json

import pytest

from lib.transcript import MessageInfo, read_last_assistant_text, read_transcript


def write_jsonl(path, entries):
    """Write a list of dicts as JSONL."""
    with open(path, "w") as f:
        for entry in entries:
            f.write(json.dumps(entry) + "\n")


def make_assistant_entry(text=None, tools=None):
    """Build an assistant transcript entry."""
    content = []
    if text:
        content.append({"type": "text", "text": text})
    for tool in tools or []:
        tool_block = {"type": "tool_use", "name": tool}
        if tool == "AskUserQuestion":
            tool_block["input"] = {"question": "Which option?"}
        content.append(tool_block)
    return {"type": "assistant", "message": {"content": content}}


class TestReadTranscript:
    def test_basic_text(self, tmp_path):
        path = tmp_path / "transcript.jsonl"
        write_jsonl(path, [make_assistant_entry(text="Hello world")])
        info = read_transcript(str(path))
        assert info is not None
        assert info.text == "Hello world"
        assert info.tool_names == []
        assert info.ends_with_tool_use is False

    def test_tool_use(self, tmp_path):
        path = tmp_path / "transcript.jsonl"
        write_jsonl(path, [make_assistant_entry(tools=["Bash", "Read"])])
        info = read_transcript(str(path))
        assert info is not None
        assert info.tool_names == ["Bash", "Read"]
        assert info.last_tool_name == "Read"
        assert info.ends_with_tool_use is True
        assert info.text is None

    def test_mixed_content(self, tmp_path):
        path = tmp_path / "transcript.jsonl"
        write_jsonl(path, [make_assistant_entry(text="Let me help", tools=["Bash"])])
        info = read_transcript(str(path))
        assert info.text == "Let me help"
        assert info.tool_names == ["Bash"]
        assert info.ends_with_tool_use is True

    def test_returns_last_assistant(self, tmp_path):
        path = tmp_path / "transcript.jsonl"
        write_jsonl(path, [
            make_assistant_entry(text="First"),
            {"type": "user", "message": {"content": "ok"}},
            make_assistant_entry(text="Second"),
        ])
        info = read_transcript(str(path))
        assert info.text == "Second"

    def test_ask_user_question_input(self, tmp_path):
        path = tmp_path / "transcript.jsonl"
        write_jsonl(path, [make_assistant_entry(tools=["AskUserQuestion"])])
        info = read_transcript(str(path))
        assert info.ask_user_question_input == {"question": "Which option?"}

    def test_empty_file(self, tmp_path):
        path = tmp_path / "transcript.jsonl"
        path.write_text("")
        assert read_transcript(str(path)) is None

    def test_nonexistent_file(self):
        assert read_transcript("/nonexistent/path.jsonl") is None

    def test_none_path(self):
        assert read_transcript(None) is None

    def test_malformed_jsonl(self, tmp_path):
        path = tmp_path / "transcript.jsonl"
        path.write_text("not json\n{bad\n" + json.dumps(make_assistant_entry(text="Valid")) + "\n")
        info = read_transcript(str(path))
        # Should skip bad lines and return the valid entry
        assert info is not None
        assert info.text == "Valid"

    def test_string_content_block(self, tmp_path):
        """Test handling of plain string content blocks (not dict)."""
        path = tmp_path / "transcript.jsonl"
        entry = {"type": "assistant", "message": {"content": ["plain string text"]}}
        write_jsonl(path, [entry])
        info = read_transcript(str(path))
        assert info.text == "plain string text"


class TestReadLastAssistantText:
    def test_basic(self, tmp_path):
        path = tmp_path / "transcript.jsonl"
        write_jsonl(path, [make_assistant_entry(text="Hello")])
        assert read_last_assistant_text(str(path)) == "Hello"

    def test_skips_tool_only(self, tmp_path):
        path = tmp_path / "transcript.jsonl"
        write_jsonl(path, [
            make_assistant_entry(text="Has text"),
            make_assistant_entry(tools=["Bash"]),  # tool-only, no text
        ])
        result = read_last_assistant_text(str(path))
        assert result == "Has text"

    def test_empty_file(self, tmp_path):
        path = tmp_path / "transcript.jsonl"
        path.write_text("")
        assert read_last_assistant_text(str(path)) is None

    def test_none_path(self):
        assert read_last_assistant_text(None) is None

    def test_nonexistent(self):
        assert read_last_assistant_text("/no/such/file.jsonl") is None
