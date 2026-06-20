#!/usr/bin/env python3
"""Emit a synthetic Claude Code .jsonl transcript for carry-cost test scenarios.
Each assistant message with a tool_use is one 'turn' (one model call that re-sends
all prior context). The matching tool_result lands in the next user message."""
import json
import sys

_n = 0


def _id():
    global _n
    _n += 1
    return f"toolu_{_n:04d}"


def turn(name, inp, result):
    tid = _id()
    asst = {"type": "assistant", "message": {"role": "assistant",
            "content": [{"type": "tool_use", "id": tid, "name": name, "input": inp}]}}
    usr = {"type": "user", "message": {"role": "user",
           "content": [{"type": "tool_result", "tool_use_id": tid, "content": result}]}}
    return [json.dumps(asst), json.dumps(usr)]


def scenario(name):
    L = []
    if name == "early_big":
        # turn 1: a big read (4000 chars ~= 1000 tok). Then 9 tiny turns.
        L += turn("Read", {"file_path": "/big.py"}, "B" * 4000)
        for i in range(9):
            L += turn("Bash", {"command": f"echo {i}"}, "ok")
    elif name == "late_big":
        # 9 tiny turns, THEN the big read on the last turn (carry ~0)
        for i in range(9):
            L += turn("Bash", {"command": f"echo {i}"}, "ok")
        L += turn("Read", {"file_path": "/big.py"}, "B" * 4000)
    elif name == "mixed":
        L += turn("Read", {"file_path": "/early.py"}, "E" * 2000)   # early, carries far
        for i in range(4):
            L += turn("Bash", {"command": f"step {i}"}, "x" * 100)
        L += turn("Read", {"file_path": "/late.py"}, "L" * 2000)    # late, carries little
        L += turn("Bash", {"command": "done"}, "ok")
    elif name == "demo":
        # a believable 24-turn session: a big CLAUDE.md + a big MCP result land EARLY,
        # an equally-big file is read near the END. Same sizes, wildly different carry.
        L += turn("Read", {"file_path": "CLAUDE.md"}, "C" * 6000)               # turn 1, big, early
        L += turn("Read", {"file_path": "src/server.py"}, "S" * 2000)
        L += turn("Bash", {"command": "mcp__github__list_issues"}, "I" * 6800)  # turn 3, big MCP result, early
        for i in range(18):
            L += turn("Bash", {"command": f"run step {i}"}, "x" * 120)
        L += turn("Read", {"file_path": "tests/test_late.py"}, "T" * 6000)      # turn 22, big, but LATE
        L += turn("Edit", {"file_path": "src/server.py"}, "edited")
        L += turn("Bash", {"command": "pytest -q"}, "y" * 300)
    elif name == "single":
        L += turn("Read", {"file_path": "/only.py"}, "O" * 800)
    else:
        sys.stderr.write(f"unknown scenario: {name}\n"); sys.exit(2)
    print("\n".join(L))


if __name__ == "__main__":
    scenario(sys.argv[1] if len(sys.argv) > 1 else "early_big")
