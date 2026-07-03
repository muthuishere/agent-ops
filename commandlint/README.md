# commandlint

A custom slash command in `.claude/commands/*.md` is a prompt you run by name — and it can run shell with `` !`…` `` and splice whatever you type as `$ARGUMENTS` straight into it. That's the sharp one: `` !`git log $ARGUMENTS` `` turns a slash command into arbitrary command execution. The quieter failures: a command that runs bash the `allowed-tools` line doesn't permit (so it silently never executes), `$ARGUMENTS` used with no `argument-hint` (nobody knows to pass them), or no `description` (the model's SlashCommand tool won't know when to call it). commandlint reads your command files and flags all of it.

## Install — there's nothing to install

```bash
git clone https://github.com/muthuishere/agent-ops
python3 agent-ops/commandlint/commandlint                 # default: ./.claude/commands
python3 agent-ops/commandlint/commandlint path/to/cmd.md     # lint one file
```

## What it does

- **Command injection** (HIGH) — `$ARGUMENTS` / `$1` interpolated into a `` !`…` `` bash exec line. Whatever the user types lands in the shell. Flagged even when quoted (quoting helps, it isn't a guarantee).
- **Dead bash** (WARN) — the body runs `` !`…` `` but `allowed-tools` is set and omits `Bash`, so the step is blocked and the command runs without it.
- **Over-broad grant** (WARN) — `allowed-tools` grants unrestricted `Bash`; also flags mis-cased (`read` → `Read`, grants nothing) and unknown tool names. `mcp__…` accepted.
- **Args ↔ hint mismatch** (WARN) — `$ARGUMENTS` used with no `argument-hint`, or an `argument-hint` whose body never consumes args.
- **Discoverability / dead command** — missing `description` (WARN — thin in `/help`, the SlashCommand tool won't route to it), empty body (HIGH — does nothing).
- **Broken `@file` reference** (INFO) — an `@path` (resolved from the project root) that doesn't exist won't inline anything.

Heuristic, not a sandbox — reads the frontmatter and body; it never executes the command or its bash. Namespaced subdirectory commands are discovered too.

Exit `0` = healthy, `1` = at least one HIGH finding.

## Why it exists

The slash command is the one bit of agent config a teammate runs without reading. A `` !`…$ARGUMENTS` `` in someone's shared `/deploy` command is a shell handed to whoever types it. Full write-up: [Your slash command is a shell](https://deemwar.com/insights/your-slash-command-is-a-shell).

## Tests

```bash
./test_commandlint.sh        # 20/20 checks
```

---

Part of **[agent-ops](https://github.com/muthuishere/agent-ops)** — small, dependency-light tools for running AI coding agents in production, **built & run by [deemwar](https://deemwar.com)**.

Running coding-agent fleets and hitting these same walls? **[Let's talk → deemwar.com/contact](https://deemwar.com/contact)**

MIT © deemwar
