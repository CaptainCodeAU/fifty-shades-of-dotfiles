#!/usr/bin/env python
# /// script
# requires-python = ">=3.11"
# dependencies = ["pytest"]
# ///
"""Tests for summary text extraction."""

import pytest

from lib.summary import (
    SummaryConfig,
    extract_last_question,
    extract_summary,
    find_action_start,
    split_sentences,
)


class TestSplitSentences:
    def test_basic(self):
        assert split_sentences("Hello. World.") == ["Hello.", "World."]

    def test_question_and_exclamation(self):
        result = split_sentences("What? Yes! Done.")
        assert result == ["What?", "Yes!", "Done."]

    def test_single_sentence(self):
        assert split_sentences("Just one.") == ["Just one."]

    def test_no_punctuation(self):
        assert split_sentences("No ending punctuation") == ["No ending punctuation"]


class TestFindActionStart:
    def test_finds_action_verb(self):
        sentences = ["Here is context.", "I've Created the file.", "Done."]
        assert find_action_start(sentences) == 1

    def test_finds_fixed(self):
        sentences = ["Some preamble.", "Fixed the bug.", "It works now."]
        assert find_action_start(sentences) == 1

    def test_no_action_verb(self):
        sentences = ["This is a sentence.", "Another one."]
        assert find_action_start(sentences) == 0

    def test_empty_list(self):
        assert find_action_start([]) == 0

    def test_case_insensitive(self):
        sentences = ["created the file."]
        assert find_action_start(sentences) == 0  # lowercase 'created' matches via IGNORECASE


class TestExtractSummary:
    def test_empty_text(self):
        assert extract_summary(None) == "Task completed"
        assert extract_summary("") == "Task completed"

    def test_action_start_default(self):
        text = "Let me explain. I've Created a new component. It handles routing."
        result = extract_summary(text)
        assert result.startswith("I've Created")

    def test_beginning_start(self):
        text = "Let me explain. I've Created a new component. It handles routing."
        config = SummaryConfig(start="beginning")
        result = extract_summary(text, config)
        assert result.startswith("Let me explain.")

    def test_sentence_limit(self):
        text = "First. Second. Third. Fourth."
        config = SummaryConfig(max_sentences=2, start="beginning")
        result = extract_summary(text, config)
        assert result == "First. Second."

    def test_character_mode(self):
        text = "Short. This is a much longer sentence that goes on and on."
        config = SummaryConfig(mode="characters", max_characters=20, start="beginning")
        result = extract_summary(text, config)
        # First sentence always included, truncated if over limit
        assert len(result) <= 20 or result == "Short."

    def test_character_mode_truncation(self):
        text = "This is a single very long sentence that exceeds the character limit by quite a lot."
        config = SummaryConfig(mode="characters", max_characters=30, start="beginning")
        result = extract_summary(text, config)
        # Should be truncated with ...
        assert result.endswith("...")
        assert len(result) <= 30

    def test_single_sentence(self):
        result = extract_summary("Done.")
        assert result == "Done."

    def test_no_action_verb_falls_back_to_beginning(self):
        text = "The system is configured. Everything looks good."
        result = extract_summary(text)
        # find_action_start returns 0 when no action found, so starts from beginning
        assert result.startswith("The system is configured.")

    def test_whitespace_only(self):
        assert extract_summary("   ") == "Task completed"


class TestExtractLastQuestion:
    def test_finds_question(self):
        text = "I did the thing. Do you want me to continue?"
        assert extract_last_question(text) == "Do you want me to continue?"

    def test_multiple_questions(self):
        text = "Is this right? Should I proceed? What do you think?"
        assert extract_last_question(text) == "What do you think?"

    def test_no_question(self):
        text = "I completed the task. Everything is done."
        assert extract_last_question(text) is None

    def test_empty(self):
        assert extract_last_question(None) is None
        assert extract_last_question("") is None
