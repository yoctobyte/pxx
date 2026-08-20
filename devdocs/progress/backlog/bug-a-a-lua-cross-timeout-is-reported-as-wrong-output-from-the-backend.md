---
slug: bug-a-a-lua-cross-timeout-is-reported-as-wrong-output-from-the-backend
track: A
type: bug
prio: 50
blocked-by: []
summary: "test-lua-cross runs each lua script under qemu with a hardcoded `timeout 120` and then diffs the captured stdout against a .expected file. A timeout truncates got.txt, the diff fails, and the recipe reports a per-target output mismatch — which reads as a cross-backend miscompile on whichever of arm32/i386/riscv32/aarch64 happened to be slow. test-core:3553 carries the same class one severity lower. Filed by Track T, which owns the harness but not the Makefile."
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
