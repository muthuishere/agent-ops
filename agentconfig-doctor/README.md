# agentconfig-doctor

The rest of the agent-ops config linters each check one surface — permissions, hooks, MCP servers, skills, subagents, slash commands, ignore files, the lethal trifecta. agentconfig-doctor runs them all over one repo and gives you a single verdict. "Is my Claude Code setup sane?" becomes one command instead of nine.

## Install — there's nothing to install

```bash
git clone https://github.com/muthuishere/agent-ops
python3 agent-ops/agentconfig-doctor/agentconfig-doctor              # checks ./
python3 agent-ops/agentconfig-doctor/agentconfig-doctor path/to/repo
python3 agent-ops/agentconfig-doctor/agentconfig-doctor --list       # show the checks
```

## What it does

Runs each sibling check against the right target in your repo and rolls the results into one table:

| check | looks at |
|---|---|
| `perm-audit` | `.claude/settings.json` permissions |
| `hooklint` | `.claude/settings.json` hooks |
| `mcp-audit` | `.mcp.json` servers |
| `trifecta-scan` | the lethal trifecta across mcp + settings |
| `skill-lint` | `SKILL.md` |
| `context-lint` | `CLAUDE.md` / `AGENTS.md` |
| `subagentlint` | `.claude/agents/*.md` |
| `commandlint` | `.claude/commands/*.md` |
| `ignorelint` | `.gitignore` / `.claudeignore` vs secret files |

- **Self-discovering** — it runs whichever of these tools are present in your agent-ops checkout. A check you don't have yet is simply skipped and appears automatically once it's there.
- **Per-target** — a check whose file/dir doesn't exist in the repo is shown `n/a`, not failed.
- **One verdict** — `✓ clean`, `● notes` (warnings only), or `✗ findings` per check, then a one-line roll-up.

It runs the checks; it doesn't reimplement them — each finding's detail comes from running the underlying tool directly. Exit `0` = every check clean, `1` = at least one check found a failing finding or errored.

## Why it exists

Agent config sprawls across a dozen files most people never audit together. One `.claude/settings.json` typo, one over-scoped subagent, one `.env` you forgot to ignore — each is invisible on its own. A single "doctor" pass is how you catch them before they ship. Full write-up: [One command to audit your whole agent setup](https://deemwar.com/insights/one-command-to-audit-your-agent-setup).

## Tests

```bash
./test_agentconfig_doctor.sh        # 15/15 checks (runs the real sibling tools)
```

---

Part of **[agent-ops](https://github.com/muthuishere/agent-ops)** — small, dependency-light tools for running AI coding agents in production, **built & run by [deemwar](https://deemwar.com)**.

Running coding-agent fleets and hitting these same walls? **[Let's talk → deemwar.com/contact](https://deemwar.com/contact)**

MIT © deemwar
