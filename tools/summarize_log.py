"""Summarize the last Hero Lifespans spike run from a completed Lua.log."""

from __future__ import annotations

import argparse
from pathlib import Path
import re


MARKER = "[HLS]"
SPIKE_STATUS = re.compile(r"^\[HLS\]\[SPIKE [^]]+\].*\b(PASS|FAIL|UNVERIFIED)$")
GAMEPLAY_STATUS = re.compile(r"^\[HLS\]\[DEV (?!UI\]|GAMEPLAY\])[^]]+\] turn=\S+ player=\S+ stamp=\S+ (PASS|FAIL|UNVERIFIED)\b")
UI_STATUS = re.compile(r"^\[HLS\]\[DEV UI\] (PASS|FAIL|UNVERIFIED)\b")


def summarize(text: str) -> tuple[list[str], dict[str, int]]:
    lines = [line[line.index(MARKER):].strip() for line in text.splitlines() if MARKER in line]
    counts = {status: 0 for status in ("PASS", "FAIL", "UNVERIFIED")}
    for line in lines:
        if "[SUMMARY]" in line:
            continue
        match = SPIKE_STATUS.match(line) or GAMEPLAY_STATUS.match(line) or UI_STATUS.match(line)
        if match:
            counts[match.group(1)] += 1
    return lines, counts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path, help="Lua.log after Civilization VI exits")
    args = parser.parse_args()
    lines, counts = summarize(args.log.read_text(encoding="utf-8-sig", errors="replace"))
    if not lines:
        print("No [HLS] log records found.")
        return 2
    for line in lines:
        print(line)
    print("Observed result lines: " + ", ".join(f"{count} {status}" for status, count in counts.items()))
    print("UNVERIFIED is an open runtime check; it is not a pass.")
    return 1 if counts["FAIL"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
