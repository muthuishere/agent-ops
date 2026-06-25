# storyboard-doctor

Pre-flight an auto-demo storyboard JSON and catch the timing/escaping mistakes
that otherwise cost you a full `produce.ts` render to discover — a voiceover
running longer than its card, a caption timed past a trimmed terminal segment, an
anchor to a timeline entry that doesn't exist, or a VHS `Type` line that breaks the
tape parser.

## Install — there's nothing to install

```bash
git clone https://github.com/muthuishere/agent-ops
python3 agent-ops/storyboard-doctor/storyboard-doctor my-demo.story.json        # run before produce.ts
python3 agent-ops/storyboard-doctor/storyboard-doctor my-demo.story.json --cli-ceiling 12 --rate 2.7
```

## What it does

- **card VO overflow** — flags a `card:` voiceover whose estimated speech runs longer than the card's `duration`.
- **terminal VO overflow** — flags a `vhs:` voiceover longer than the segment likely holds. CLI segment length is *estimated* from the number of commands the tape runs (produce trims inter-command dead air, so `Sleep` values don't lengthen it); override with `--cli-ceiling`.
- **captions past the segment** — flags a `vhs:` caption whose `to` runs past the segment's estimated end, so it never renders.
- **broken anchors / refs** — a voiceover anchored to a timeline entry that doesn't exist (which makes `produce.ts` fail), a caption on an undefined segment, a timeline pointing at a missing card.
- **risky `Type` lines** — inline quotes + pipe/braces that break the VHS tape parser. Speech estimate defaults to 2.6 words/sec; override with `--rate`.

Exit `0` = clean, `1` = problems found.

## Why it exists

Built from a session of house demos where this same handful of issues forced ~10 re-renders — all of them detectable from the storyboard alone, before `produce.ts` ever runs.

## Tests

```bash
./test_storyboard_doctor.sh        # 13/13 checks
```

---

Part of **[agent-ops](https://github.com/muthuishere/agent-ops)** — 29 small, dependency-light tools for running AI coding agents in production, **built & run by [deemwar](https://deemwar.com)**.

Running coding-agent fleets and hitting these same walls? **[Let's talk → deemwar.com/contact](https://deemwar.com/contact)**

MIT © deemwar
