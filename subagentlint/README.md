# subagentlint

`skill-lint` checks whether your `SKILL.md` will actually get used. subagentlint does the same for the other on-demand surface: the **subagent definitions** in `.claude/agents/*.md`. Claude auto-delegates to a subagent from its `description` alone — a vague one silently never gets picked. Its `tools:` line decides how much it can do — omit it and the subagent inherits *every* tool, Bash and Write included. A typo'd tool name is silently dropped; a duplicate `name` collides with another agent; a frontmatter-only file ships with no instructions at all. subagentlint catches all of it before you wonder why an agent never fires.

## Install — there's nothing to install

```bash
git clone https://github.com/muthuishere/agent-ops
python3 agent-ops/subagentlint/subagentlint                 # default: ./.claude/agents
python3 agent-ops/subagentlint/subagentlint path/to/agent.md   # lint one file
```

## What it does

- **Won't load** (HIGH) — missing/invalid `---` frontmatter, missing `name`, or missing `description`.
- **Won't route** (WARN) — a `description` that's too short or has no "use when…" trigger cue, so auto-delegation skips it (same failure mode `skill-lint` catches for skills).
- **Name collisions** (HIGH) — two subagents sharing a `name`; off-convention names (not lowercase-kebab) as WARN; a `name` that differs from its filename as INFO.
- **Tool footguns** (WARN) — no `tools:` line (inherits *all* tools incl. Bash/Write), `tools: '*'`, a mis-cased built-in (`read` → `Read`, silently not granted), an unknown tool name, or powerful tools (`Bash`/`Write`/`Edit`) granted to an agent whose description reads read-only. MCP tools (`mcp__…`) are accepted.
- **Other** — an unrecognised `model`, or an empty body with no system prompt (WARN).

Heuristic, not a schema validator — reads the frontmatter and body and flags shapes that don't load or don't route; it never runs the subagent.

Exit `0` = healthy, `1` = at least one HIGH finding.

## Why it exists

Subagents are the fastest-growing piece of agent config, and the one with no feedback loop: a broken skill errors, but a subagent that never routes just sits there silent. The cost shows up as "why didn't it use my reviewer?" three weeks later. Full write-up: [The subagent that never gets picked](https://deemwar.com/insights/the-subagent-that-never-gets-picked).

## Tests

```bash
./test_subagentlint.sh        # 20/20 checks
```

---

Part of **[agent-ops](https://github.com/muthuishere/agent-ops)** — small, dependency-light tools for running AI coding agents in production, **built & run by [deemwar](https://deemwar.com)**.

Running coding-agent fleets and hitting these same walls? **[Let's talk → deemwar.com/contact](https://deemwar.com/contact)**

MIT © deemwar
