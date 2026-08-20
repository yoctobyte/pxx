---
slug: bug-a-a-lua-cross-timeout-is-reported-as-wrong-output-from-the-backend
track: A
type: bug
prio: 50
blocked-by: []
summary: "test-lua-cross runs each lua script under qemu with a hardcoded `timeout 120` and then diffs the captured stdout against a .expected file. A timeout truncates got.txt, the diff fails, and the recipe reports a per-target output mismatch — which reads as a cross-backend miscompile on whichever of arm32/i386/riscv32/aarch64 happened to be slow. test-core:3553 carries the same class one severity lower. Filed by Track T, which owns the harness but not the Makefile."
status: done
owner: claude-A
---

# A lua cross timeout is reported as wrong output from the backend

Filed by **plexus-T** out of
[[bug-t-makefile-inner-timeouts-are-invisible-to-testmgrs-contention-logic]], which
measured this class across all ten of the Makefile's hardcoded ceilings. T owns the
tool, not the `Makefile`, so the recipe-side fix belongs to the lane that owns what the
recipe tests.

## The finding

`Makefile:8997`, inside `test-lua-cross`:

```make
	    timeout 120 tools/run_target.sh $$T $(TESTTMP)/pxx_lua_$$T 2>/dev/null > $(TESTTMP)/pxx_lua_got.txt; \
	    if diff -u "$$exp" $(TESTTMP)/pxx_lua_got.txt > $(TESTTMP)/pxx_lua_diff.txt; then \
	      echo "test-lua-cross: PASS $$T $$(basename $$p)"; \
	    else ... fail=1
```

The status is discarded by the `;`. When the emulated run is killed at 120s,
`pxx_lua_got.txt` holds a **truncated** stream, the `diff` against `.expected` fails,
and the recipe reports a per-target output mismatch.

That report's stated subject is **the backend**: lua, built by pxx for `$$T`, printing
the wrong thing under qemu. It is the single most expensive misattribution this harness
can produce — a cross-codegen investigation opened against whichever of
`$(LUA_CROSS_TARGETS)` happened to be slow that evening. **A truncated stream is not a
wrong answer, and it must never reach a `diff`.**

The load sensitivity is real and specific: every one of these runs is **emulated**, so
its wall time is a function of box contention in a way a native job's is not, against a
ceiling written as a constant.

## The second, milder site in this lane

`Makefile:3553` (`test-core`):

```make
	test "$$(timeout 20 $(TESTTMP)/test_writeln_nonfinite26)" = "$$(printf ' Inf\n ...')"
```

Command substitution discards `timeout`'s exit 124; what fails is `test`, so make
reports `Error 1`. This one **loses** a signal rather than inventing one — a timeout is
indistinguishable from a wrong value, but nothing false is asserted about a backend.
Lower severity, same one-line shape of fix.

## The fix shape

Capture the status and branch on 124 before comparing:

```make
	    timeout 120 tools/run_target.sh ... > got.txt; rc=$$?; \
	    if [ "$$rc" = "124" ]; then echo "test-lua-cross: TIMEOUT $$T $$(basename $$p)"; fail=1; \
	    elif diff -u ...
```

Whether a timeout should be a `fail` or a distinct advisory status is Track A's call.
What matters is that it is not reported as a **diff**.

**Do not fix this by raising the constant.** That trades a false red for a slower suite
and leaves a reader unable to tell the two kinds of red apart — the cost six closed
timeout tickets kept paying.

## What Track T already did, and why it is not enough here

`testmgr` now records each job's learned baseline beside its duration in the report, and
retries a failure that ran far longer than its baseline while a co-tenant run was live.
That makes an overlong red legible and, under contention, retried. It cannot reach this
one: the failure is a `diff`, and no duration signal can say *the comparison should not
have been made*. Only the recipe saw the 124.

## Gate

Track A's: `make test` + self-host byte-identical. `test-lua-cross` skips cleanly with
no lua tree at `$(LUA_SRC)` and skips per-target when `qemu-$$T` is absent, so verify
with at least one emulator installed.

## 2026-08-21 — fixed, at SEVEN sites rather than the two filed

### Grepped for the siblings before closing

`normalise-dont-special-case.md`'s rule — fix one arm of a double case and go
looking for the other — turned two sites into seven. Every `timeout N` in the
`Makefile` was checked, and five of them discarded the 124:

| site | what the report said before | severity |
| --- | --- | --- |
| `test-lua-cross` (120s, qemu) | per-target **output mismatch** | the filed one: invents a cross-backend miscompile |
| `test-uforth` corpus (180s) | **`DIFF <file>`** vs the CPython oracle | worse than the filed one, see below |
| `test-uforth` word sets (900s) | **`DIFF word set <f>`** | same |
| `test_writeln_nonfinite` (20s) | make `Error 1` | filed; loses a signal, invents nothing |
| `test_nilpy_str_repeat` (60s) | make `Error 1` | same, and the test's *whole point* is that a regression is a hang |
| `test_nilpy_float_repeat_typeerror` (20s) | make `Error 1` | same |
| tk under Xvfb (120s) | `EXITED NONZERO under Xvfb` | true but useless: a hang and a crash read alike |

### The uforth pair is worse than the ticket's own example

Those two run **pxx and CPython concurrently**, each under its own `timeout`, then
`wait $pp || true; wait $cp || true` — both statuses thrown away — and diff the
two captures. So when the box is loaded and **either** side is killed, the recipe
prints `DIFF <file>` with a unified diff of pxx's output against CPython's. That
is not merely a misattributed red: it is a **differential** red, the single most
persuasive kind, produced by comparing a truncated stream against a complete one.
Same failure class as the filed one, one notch more convincing and therefore more
expensive.

Note the milder-looking third row: `test_nilpy_str_repeat`'s comment says the
large sizes exist because *"the old quadratic routine could not finish this
file"*. A timeout there is the regression it was written to catch, and it was
being reported as a wrong value.

### The fix

One shape everywhere: capture the status, branch on 124 **before** any comparison,
and say `TIMEOUT` with the ceiling and the fact that it is not a mismatch.
Timeouts stay **failures** (nothing silently passes) but are never a `diff`, which
is what the ticket asked for. The uforth pair reports both statuses (`pxx=$prc
oracle=$crc`) so the reader can see which side was killed. The `wait ... || true`
became `if wait $pp; then prc=0; else prc=$?; fi` — `|| true` was there to survive
a nonzero exit, and that is still true, but now the value is kept.

**No constant was raised**, per the ticket's own instruction. The trade it warns
against — a false red becomes a slow suite and the reader still cannot tell the
two reds apart — is exactly what the labelling avoids.

The tk site was left as `exit 1` rather than a distinct status because it is a
`@if command -v xvfb-run` block with no accumulator to fold into.

### Verified

Each branch exercised in isolation with a synthetic 124 (`timeout 1 sleep 5`) and
with a clean exit, including the concurrent `wait` pair, so the timeout arm is
executed rather than merely written. The four rewritten expected-output
assertions re-run by hand against their real binaries and still match — one of
them caught a stray quote the rewrite introduced, before it reached the gate.
`test-lua-cross` still parses under `make -n`.

`test-lua-cross` and `test-uforth` need lua/uforth trees plus emulators to run for
real; they are not in the quick tier and Track T sweeps them, so what is verified
here is the branch logic and that every recipe still parses and passes when
nothing times out.

### Gate

`make compiler/pascal26` (byte-identical fixedpoint) + `tools/gate.sh quick`. No
compiler source changed — this is Makefile-only.

## Log
- 2026-08-21 — resolved, commit 525ef7f2c.
