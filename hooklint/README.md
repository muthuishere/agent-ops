# hooklint

Claude Code hooks run *automatically* on agent events — every tool call, every prompt, every stop — so the failure modes are quiet. A typo'd event name silently never fires. A blanket `PreToolUse` matcher runs before every tool and can wedge all of them. A `command` that echoes a secret or runs `rm -rf` does it without ever asking you. hooklint reads the `hooks` block of your `.claude/settings.json` and flags those footguns before they fire.

## Install — there's nothing to install

```bash
git clone https://github.com/muthuishere/agent-ops
python3 agent-ops/hooklint/hooklint                  # default: ./.claude/settings.json
python3 agent-ops/hooklint/hooklint path/settings.json   # lint a specific file
```

## What it does

- Catches **event names that never fire** — a mis-cased `PreTooluse` or an invented `OnEveryThing` is silently ignored by Claude Code (HIGH); hooklint names the typo and the event it meant.
- Catches **malformed shapes that don't run** — a flat entry missing its `{matcher, hooks:[…]}` wrapper (HIGH), a non-`command` `type` (WARN), an empty command (WARN), an invalid matcher regex (WARN).
- Flags **dangerous commands that auto-run** on a matched event — `rm -rf`, `git push --force`, `curl … | sh`, `eval`, `--no-verify` (HIGH).
- Flags **secret exposure** — a hook that echoes a `*_KEY/_TOKEN/_SECRET` env var or runs bare `env`/`printenv` into hook output, or carries a hard-coded `sk-…`/`ghp_…`/AWS-key literal (HIGH).
- Notes **blanket `PreToolUse`/`PostToolUse` matchers** that run on every tool call (WARN — latency, and a flaky `PreToolUse` can block all tools), **network egress** in a hook (WARN), and **`Stop`/`SubagentStop` loop risk** (INFO).

Heuristic, not a sandbox: hooklint reads the config statically — it does not execute your hooks. No hooks configured, or no settings file, is the safe default and exits clean.

Exit `0` = no high-severity issues, `1` = at least one HIGH/CRITICAL finding.

## Why it exists

A hook is the one piece of agent config that acts on its own. The quietest failure — a hook that's silently never running, or one that leaks a key on every Bash call — is exactly the kind of thing you don't notice until it bites. Full write-up: [The Claude hook that never fires](https://deemwar.com/insights/the-claude-hook-that-never-fires).

## Tests

```bash
./test_hooklint.sh        # 20/20 checks
```

---

Part of **[agent-ops](https://github.com/muthuishere/agent-ops)** — small, dependency-light tools for running AI coding agents in production, **built & run by [deemwar](https://deemwar.com)**.

Running coding-agent fleets and hitting these same walls? **[Let's talk → deemwar.com/contact](https://deemwar.com/contact)**

MIT © deemwar
