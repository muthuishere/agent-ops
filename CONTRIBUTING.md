# Contributing to agent-ops

Thanks for wanting to add to the operational layer. This repo is a collection of
**small, dependency-light tools for AI coding agents** — every tool earns its place by
fixing one real failure we hit running autonomous agent fleets in production.

The bar is deliberately simple, and CI enforces it for you. If you mirror an existing
tool you'll be done in one sitting.

## The shape of a tool

One tool is one directory at the repo root. Use [`perm-audit/`](perm-audit/) as your
reference — copy its layout and adapt.

```
my-tool/
├── my-tool              # the tool: ONE self-contained executable file
├── test_my_tool.sh      # its test suite (note: underscores)
└── README.md            # the house-style write-up
```

Three files, nothing else required.

### 1. The script — `my-tool/my-tool`

- **One file**, named exactly like its directory. `chmod +x` it.
- **Python 3 or bash only.** No `pip install`, no `npm`, no third-party deps — nothing
  beyond a stock interpreter on a clean machine. That "no install, run it directly"
  promise is the whole point; a dependency breaks it.
- **Reads its target** from a path argument (or stdin where that's natural), so it drops
  into a hook or CI line unchanged.
- **Exits non-zero when it finds a problem**, zero when clean. That's what lets a tool
  sit in a Stop hook or a CI step and actually gate something.
- **Heuristic and honestly labelled.** These are estimates, not bills. If a finding is
  uncertain, say so in the output — don't dress a guess up as a fact.
- **Never prints a secret's value.** Tools that touch credentials (see `leaklint`) are
  redact-by-design: flag the leak, never reprint it.

### 2. The test — `my-tool/test_my_tool.sh`

- A plain bash script that builds its own synthetic fixtures (temp files / temp repos),
  runs the tool against them, and checks the output and exit code.
- Self-contained: no network, no fixed paths outside the repo, safe to run anywhere.
- Counts `PASS`/`FAIL` and **exits non-zero if anything failed** — that's the signal CI
  reads. Copy the `ok()` / `bad()` helper pattern from
  [`perm-audit/test_perm_audit.sh`](perm-audit/test_perm_audit.sh).

Run it locally before you push:

```bash
bash my-tool/test_my_tool.sh
```

### 3. The README — `my-tool/README.md`

Lead with the **failure it prevents**, then usage, then what the output means. Match the
voice of the existing per-tool READMEs: concrete, plain, no hype. Add a one-line row for
your tool to the matching table in the root [`README.md`](README.md).

## CI: nothing to wire up

CI is a **self-discovering matrix** — it scans every top-level directory for a
`test_*.sh` and runs it as its own job. Add your tool with its test and CI picks it up on
the pull request with **no workflow edit**. A green run means every tool's suite passed.

So the entire checklist is: *does `bash my-tool/test_my_tool.sh` pass?* If yes, CI will be
green too.

## Before you open the PR

- [ ] Tool is one self-contained file, executable, no non-stdlib dependencies.
- [ ] Exits non-zero on a finding, zero when clean.
- [ ] `test_my_tool.sh` exists, is self-contained, and passes locally.
- [ ] `README.md` explains the failure it prevents; root README table has a row.
- [ ] No secret values are ever printed.

Keep one tool per pull request — it keeps review fast and the history clean.

## License

By contributing you agree your work is released under the repo's
[LICENSE](LICENSE).

Built and run by [deemwar](https://deemwar.com). Questions, or putting agents to work on
code that matters? **[Talk to us](https://deemwar.com/contact).**
