"""Text summarization logic for Claude Code hooks."""

import re
from dataclasses import dataclass


@dataclass
class SummaryConfig:
    """Configuration for summary extraction."""

    mode: str = "sentences"  # "sentences" or "characters"
    max_sentences: int = 2
    max_characters: int = 200
    start: str = "action"  # "action" or "beginning"


# Action verb patterns to look for at the start of sentences
ACTION_PATTERNS = [
    r"(?:I've |I have |I )?(Created|Fixed|Added|Updated|Removed|Deleted|Modified|Implemented|Refactored|Changed|Built|Set up|Configured|Installed|Moved|Renamed|Wrote|Generated|Completed|Finished|Done|Made)",
    r"(?:I've |I have |I )?(successfully (?:created|fixed|added|updated|removed|deleted|modified|implemented|refactored|changed|built|set up|configured|installed|moved|renamed|wrote|generated|completed|finished))",
]


def split_sentences(text: str) -> list[str]:
    """Split text into sentences.

    Args:
        text: Text to split

    Returns:
        List of sentences
    """
    return re.split(r"(?<=[.!?])\s+", text)


def find_action_start(sentences: list[str]) -> int:
    """Find the index of the first sentence starting with an action verb.

    Args:
        sentences: List of sentences

    Returns:
        Index of first action sentence, or 0 if not found
    """
    for idx, sentence in enumerate(sentences):
        sentence = sentence.strip()
        for pattern in ACTION_PATTERNS:
            if re.match(pattern, sentence, re.IGNORECASE):
                return idx
    return 0


def extract_summary(text: str | None, config: SummaryConfig | None = None) -> str:
    """Extract a brief summary from assistant text.

    Args:
        text: Text to summarize
        config: Summary configuration settings

    Returns:
        Extracted summary or default message
    """
    if not text:
        return "Task completed"

    if config is None:
        config = SummaryConfig()

    # Clean up the text
    text = text.strip()

    # Split into sentences
    sentences = split_sentences(text)

    # Determine start index based on mode
    start_idx = 0
    if config.start == "action":
        start_idx = find_action_start(sentences)

    # Build summary based on mode
    summary_parts: list[str] = []

    if config.mode == "sentences":
        # Extract first N sentences
        sentence_count = 0
        for idx in range(start_idx, len(sentences)):
            sentence = sentences[idx].strip()
            if not sentence:
                continue

            summary_parts.append(sentence)
            sentence_count += 1

            if sentence_count >= config.max_sentences:
                break

    else:  # "characters" mode
        current_length = 0

        for idx in range(start_idx, len(sentences)):
            sentence = sentences[idx].strip()
            if not sentence:
                continue

            if current_length == 0:
                # Always include at least the first sentence
                summary_parts.append(sentence)
                current_length = len(sentence)
            elif current_length + len(sentence) + 1 <= config.max_characters:
                summary_parts.append(sentence)
                current_length += len(sentence) + 1
            else:
                break

    if summary_parts:
        summary = " ".join(summary_parts)

        # Final truncation if in character mode and still too long
        if config.mode == "characters" and len(summary) > config.max_characters:
            summary = summary[: config.max_characters - 3] + "..."

        return summary

    return "Task completed"


def extract_last_question(text: str | None) -> str | None:
    """Extract the last question from text.

    Args:
        text: Text to search for questions

    Returns:
        The last question sentence, or None if not found
    """
    if not text:
        return None

    sentences = split_sentences(text)
    # Find last sentence ending with ?
    for sentence in reversed(sentences):
        if sentence.strip().endswith("?"):
            return sentence.strip()
    return None
