#!/usr/bin/env python3
"""Emit a synthetic Claude Code .jsonl transcript for a named scenario (test fixtures).
Mirrors the real shape: assistant messages carry content[] tool_use blocks; the next
user message carries tool_result blocks keyed by tool_use_id."""
import json
import sys

_n = 0


def _id():
    global _n
    _n += 1
    return f"toolu_{_n:04d}"


def use(name, inp):
    """One assistant tool_use + the matching user tool_result. Returns lines."""
    tid = _id()
    result = inp.pop("_result", "ok")
    asst = {"type": "assistant", "message": {"role": "assistant",
            "content": [{"type": "tool_use", "id": tid, "name": name, "input": inp}]}}
    usr = {"type": "user", "message": {"role": "user",
           "content": [{"type": "tool_result", "tool_use_id": tid, "content": result}]}}
    return [json.dumps(asst), json.dumps(usr)]


def emit(lines):
    print("\n".join(lines))


BIG = "x" * 4000   # a ~1000-token file payload
SMALL = "y" * 200


def scenario(name):
    L = []
    if name == "reread":
        # /big.txt read 3 times (2 redundant), /small read once
        for _ in range(3):
            L += use("Read", {"file_path": "/big.txt", "_result": BIG})
        L += use("Read", {"file_path": "/small.txt", "_result": SMALL})
    elif name == "read_after_edit":
        L += use("Read", {"file_path": "/code.py", "_result": BIG})
        L += use("Edit", {"file_path": "/code.py", "_result": "edited"})
        L += use("Read", {"file_path": "/code.py", "_result": BIG})   # the anti-pattern
    elif name == "dup_bash":
        for _ in range(3):
            L += use("Bash", {"command": "npm test", "_result": "ran tests"})
    elif name == "dup_search":
        for _ in range(2):
            L += use("Grep", {"pattern": "TODO", "path": "src", "_result": "3 matches"})
    elif name == "demo":
        # a believable session (fake paths) that shows all the patterns + a real-ish total
        app = "z" * 3200      # ~800-token source file
        readme = "r" * 2400
        cfg = "c" * 1600
        # work on app.py: read, edit, then re-read it 3 times (the anti-pattern)
        L += use("Read", {"file_path": "src/app.py", "_result": app})
        L += use("Edit", {"file_path": "src/app.py", "_result": "edited"})
        L += use("Read", {"file_path": "src/app.py", "_result": app})
        L += use("Edit", {"file_path": "src/app.py", "_result": "edited"})
        L += use("Read", {"file_path": "src/app.py", "_result": app})
        L += use("Read", {"file_path": "src/app.py", "_result": app})
        # README read twice (duplicate read)
        L += use("Read", {"file_path": "README.md", "_result": readme})
        L += use("Read", {"file_path": "README.md", "_result": readme})
        # config read once (fine), and a single edit
        L += use("Read", {"file_path": "pyproject.toml", "_result": cfg})
        # npm test run 3 times
        for _ in range(3):
            L += use("Bash", {"command": "npm test", "_result": "PASS 42 tests" * 20})
        # grep TODO twice
        for _ in range(2):
            L += use("Grep", {"pattern": "TODO", "path": "src", "_result": "src/app.py:12: TODO\n" * 8})
    elif name == "clean":
        L += use("Read", {"file_path": "/a.py", "_result": SMALL})
        L += use("Read", {"file_path": "/b.py", "_result": SMALL})
        L += use("Bash", {"command": "ls", "_result": "a b"})
        L += use("Grep", {"pattern": "foo", "path": "src", "_result": "1 match"})
    else:
        sys.stderr.write(f"unknown scenario: {name}\n"); sys.exit(2)
    emit(L)


if __name__ == "__main__":
    scenario(sys.argv[1] if len(sys.argv) > 1 else "reread")
