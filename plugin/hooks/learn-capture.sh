#!/usr/bin/env bash
set -uo pipefail

# learn-capture.sh — UserPromptSubmit + PostToolUse * hook
# Detects event type from payload structure and captures to
# $CC_STATE_DIR/.memory/buffer.md using the learning-entry format
# (see the learning capture convention rule if the project ships one).
# exit 0 always (non-blocking).

source "$(dirname "${BASH_SOURCE[0]}")/lib/cc-config.sh"

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
BUFFER_FILE="$PROJECT_ROOT/$CC_STATE_DIR/.memory/buffer.md"

PAYLOAD="$(cat 2>/dev/null || true)"
if [[ -z "$PAYLOAD" && $# -gt 0 ]]; then
  PAYLOAD="$1"
fi

python3 - "$BUFFER_FILE" "$PAYLOAD" <<'PY'
import json
import re
import sys
from pathlib import Path
from datetime import datetime, timezone


def load_existing_summaries(path):
    if not path.exists():
        return set()
    text = path.read_text()
    summaries = set()
    for line in text.splitlines():
        if line.startswith("**summary:**"):
            summaries.add(line.replace("**summary:**", "").strip().lower())
    return summaries


def append_entry(path, entry):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as f:
        f.write("\n---\n" + entry + "\n")


buffer_file = Path(sys.argv[1])
payload = sys.argv[2].strip() if len(sys.argv) > 2 else ""

if not payload:
    raise SystemExit(0)

try:
    data = json.loads(payload)
except Exception:
    raise SystemExit(0)

timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# ── UserPromptSubmit: correction detection ──────────────────────────────────
if "prompt" in data:
    prompt = data.get("prompt", "").strip()
    if not prompt:
        raise SystemExit(0)

    CORRECTION_RE = re.compile(
        r"""
        \bno[,!]\s                                                      # "no, ..." / "no! ..."
        | \bnot\s+that\b                                                # "not that"
        | \bdon'?t\s+do\s+(?:that|this)\b                              # "don't do that/this"
        | \bstop\s+(?:doing|using|adding|putting|creating)\b           # "stop doing/using X"
        | \bundo\s+(?:that|this|the\s+last)\b                          # "undo that/this/the last"
        | \bthat'?s\s+(?:wrong|incorrect|not\s+(?:right|what\s+I))\b  # "that's wrong/incorrect"
        | \byou\s+shouldn'?t\b                                          # "you shouldn't"
        | \byou\s+should\s+not\b                                        # "you should not"
        | \bwrong\s+(?:approach|direction|way|file|method|pattern|format)\b
        | \bactually,\s+I\b                                             # "actually, I meant..."
        | \bI\s+(?:said|meant|asked)\b.*\bnot\b                        # "I said not to..."
        | \bні[,!]?\s                                                   # Ukrainian "ні, ..."
        | \bне\s+так\b                                                  # Ukrainian "не так"
        | \bне\s+туди\b                                                  # Ukrainian "не туди"
        | \bнеправильно\b                                               # Ukrainian "неправильно"
        | \bincorrect\b
        | \brevert\b
        """,
        re.IGNORECASE | re.VERBOSE,
    )
    if not CORRECTION_RE.search(prompt):
        raise SystemExit(0)

    preview = prompt[:300]
    summary = f"User corrected: {preview[:80]}"

    existing = load_existing_summaries(buffer_file)
    if summary.lower() in existing:
        raise SystemExit(0)

    entry = (
        f"**type:** correction\n"
        f"**summary:** {summary}\n"
        f"**detail:** {preview}\n"
        f"**root:** [review prior conversation to identify what was wrong]\n"
        f"**resolution:** [follow the user's correction]\n"
        f"**generalization:** TODO — fill on promotion\n"
        f"**context:** [session context]\n"
        f"**destination:** library\n"
        f"**captured:** {timestamp}"
    )
    append_entry(buffer_file, entry)

# ── PostToolUse: tool error detection ───────────────────────────────────────
elif "tool_name" in data:
    tool_name = data.get("tool_name", "unknown")
    response = data.get("tool_response", {})
    if isinstance(response, str):
        try:
            response = json.loads(response)
        except Exception:
            response = {}
    if not isinstance(response, dict):
        response = {}

    is_error = response.get("is_error", False)
    error_text = str(response.get("error", "") or "")

    if not is_error and not error_text:
        raise SystemExit(0)

    # Avoid capturing writes to buffer.md itself (recursion guard)
    if "buffer.md" in error_text:
        raise SystemExit(0)

    error_preview = (error_text or "")[:300]
    summary = f"Tool error [{tool_name}]: {error_preview[:70]}"

    existing = load_existing_summaries(buffer_file)
    if summary.lower() in existing:
        raise SystemExit(0)

    entry = (
        f"**type:** mistake (candidate)\n"
        f"**summary:** {summary}\n"
        f"**detail:** Tool: `{tool_name}` — {error_preview}\n"
        f"**root:** [review prior conversation to determine why the call failed]\n"
        f"**resolution:** [to be determined on promotion]\n"
        f"**generalization:** TODO — fill on promotion\n"
        f"**context:** [session context]\n"
        f"**destination:** library\n"
        f"**captured:** {timestamp}"
    )
    append_entry(buffer_file, entry)

PY

exit 0
