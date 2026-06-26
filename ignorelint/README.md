# ignorelint

`leaklint` scans output for secret *values*. ignorelint checks the other side: the ignore files that decide which *files* git will commit and an AI agent is allowed to read. A `.env` that no rule covers is both committable and readable by the agent. A `!`-negation can quietly re-expose a key you thought was excluded. A re-include under an already-ignored directory is dead and silently does nothing. A pattern with a stray trailing space never matches at all. ignorelint reads `.gitignore` (and `.claudeignore` / `.cursorignore` / `.aiexclude`) **and the files actually on disk**, and flags the gaps.

## Install — there's nothing to install

```bash
git clone https://github.com/muthuishere/agent-ops
python3 agent-ops/ignorelint/ignorelint                  # default: current directory
python3 agent-ops/ignorelint/ignorelint path/to/repo     # lint a specific repo
```

## What it does

- **Secret files nothing ignores** (HIGH) — walks the tree, finds `.env` / `*.env` / `*.pem` / `*.key` / `id_rsa` / `*.p12` / `credentials.json` / `service-account*.json` etc., and flags any that no `.gitignore` rule excludes. Names the path only — **never the contents**. (`.env.example`/`.sample`/`*.pub` are recognised as safe.)
- **Negation that re-exposes a secret** (HIGH) — a `!`-rule un-ignoring a credential file.
- **Dead re-include** (WARN) — `!build/keep.txt` under an ignored `build/`: git can't re-include a file once its parent dir is excluded, so the rule does nothing.
- **Ignore-everything** (WARN) — a bare `*`/`**`/`/` that excludes the whole tree.
- **Trailing-whitespace patterns** (WARN) — git treats them literally, so the pattern silently never matches (and a secret it "covers" stays exposed — flagged as both).
- **Git-ignored but agent-visible** (WARN) — when a `.claudeignore`/`.cursorignore` exists, a secret that `.gitignore` excludes but the agent ignore-file doesn't: git won't commit it, but the agent can still read it.

Implements the common gitignore shapes (basename, anchored, `*`/`**`, dir-only, `!`-negation, last-match-wins) — a high-signal heuristic, not a byte-exact reimplementation of git's matcher.

Exit `0` = no high-severity issues, `1` = at least one HIGH/CRITICAL finding.

## Why it exists

The file you forgot to ignore is the one that leaks. Now that an agent reads your whole repo on every run, an unignored `.env` isn't just a commit risk — it's in the model's context. Full write-up: [The file you forgot to .gitignore](https://deemwar.com/insights/the-file-you-forgot-to-gitignore).

## Tests

```bash
./test_ignorelint.sh        # 22/22 checks
```

---

Part of **[agent-ops](https://github.com/muthuishere/agent-ops)** — small, dependency-light tools for running AI coding agents in production, **built & run by [deemwar](https://deemwar.com)**.

Running coding-agent fleets and hitting these same walls? **[Let's talk → deemwar.com/contact](https://deemwar.com/contact)**

MIT © deemwar
