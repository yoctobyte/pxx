---
slug: decide-what-should-pxx-selfcheck-assert-when-the-compiler-cannot-spawn
title: "`pxx --selfcheck` is the last item of feature-toolchain-cli-ux — but the check it is specified to run needs a subprocess the compiler does not have"
track: U
prio: 30
type: decide
status: new
blocked-by: []
owner: user
summary: "Five of the six CLI/UX flags are landed; --selfcheck is the last, and its blocker feature-release-packaging is now in done/. The spec defines check 1 as `pxx -> gen1`, then `gen1 -> gen2`, `cmp gen1 gen2` -- a real fixedpoint STEP, which requires running the freshly built binary. The compiler binary cannot spawn a process and locates itself only via ExeDir. Every in-process alternative asserts something WEAKER under the same trusted name. tools/selfcheck.sh already does the specified thing and already ships in the release tree, so doing nothing is a real option."
---

# What should `pxx --selfcheck` assert?

Raised by frankH, 2026-09-02, working `feature-toolchain-cli-ux` (oldest
actionable). Nothing is blocked on the answer — I took the next ticket.

## Why it is a fork and not a measurement

Measured: `--version`, `--where`, `--list-targets`, `--list-libraries` and
`--doctor` all answer and exit 0; `--selfcheck` is `unknown option`. Its blocker
`feature-release-packaging` is in `done/`. The compiler spawns no process
(no `PalVforkAndExec` / `PalFork` anywhere under `compiler/`) and knows only
`ExeDir`. `tools/selfcheck.sh` (46 lines) implements both checks already and is
shipped inside the unpacked release, beside `compiler/` and `MANIFEST.sha256`.

What cannot be measured is which promise the flag should make.

## The options

**(a) In-process double compile** — compile `compiler.pas` twice, `cmp`. Tests
determinism of this binary. **Not a fixedpoint step**, so it would not catch a
binary that builds a *different* compiler which then diverges.

**(b) Compile and compare to the running binary** — a genuine fixedpoint claim
and no subprocess. But it reports FAIL on any release binary built with
non-default flags, where the difference is legitimate. A check that cries wolf
on a correct install is worse than none.

**(c) Give the compiler spawn capability** and do exactly what the spec says.
Faithful, and the only option whose name matches its assertion — at the cost of
a new capability in the compiler binary, used by one diagnostic flag.

**(d) Do not add the flag; close the item and point `--help` at
`tools/selfcheck.sh`.** The "flag, not a script" principle in
`feature-toolchain-cli-ux` exists to avoid *"a litter of helper scripts that
confuse users"* — but this is one documented script that ships inside the
release tree, and it can exec, so it already does the strong check.

**Recommendation: (d), with (c) as the answer if the principle is the point.**
(a) and (b) both put a weaker or noisier assertion behind a name people will
trust, which is the failure this repo already has names for — a guard that
cannot fail, and the name not being the thing. If the flag is wanted for its own
sake, (c) is the only honest way to build it.

If (d): `feature-toolchain-cli-ux` closes, and `--help` gains one line.
