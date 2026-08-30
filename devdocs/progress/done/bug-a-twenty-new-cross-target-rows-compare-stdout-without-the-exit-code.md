---
track: A
prio: 40
type: bug
blocked-by: []
summary: "The stdout-only ratchet in tools/exit_observable_devtest.py was armed at 531 this morning (f444a4a33) and reads 551 tonight. 20 new cross-target differential rows compare stdout and not the exit status, attributed exactly to four commits in three lanes. The exposure is the shape frankS's Halt(5)-exits-0 bug lived in; the fix is mechanical. tools-devtest is red in the limited and full tiers until it lands."
status: done
owner: frank-optimize-b4
---

> **NOT a duplicate of `chore-t-make-every-cross-target-row-assert-the-exit-code` [T p45]** — checked by the
> coordinator 2026-08-30 after `progress.sh check` raised NEAR-DUP on four shared slug words. They are a
> **regression** and a **campaign**, and merging them would lose one of the two. THIS ticket is bounded: the
> ratchet was armed at 531 and reads 551, so **20 specific rows** regressed across four commits in three
> lanes, and `tools-devtest` is RED in the limited and full tiers until they land. That ticket is the
> general rollout of all 531, which needs piloting one arch at a time. Fix this one first — it is smaller,
> it clears a red tier, and it does not depend on the campaign's outcome.

# 20 new cross-target rows compare stdout without the exit code

- **Type:** bug (Track A — the rows are `Makefile` recipe lines).
- **Found:** 2026-08-30 by Track T (face 2), from the ratchet going red;
  independently seen by the coordinator. Filed by T, not fixed by T.

## The measurement, and it attributes exactly

`tools/exit_observable_devtest.py` section 3 counts rows that run
`tools/run_target.sh` with two `"$$(` captures — a cross-target differential —
and subtracts the ones that also capture `exit=$$?`. It was armed at **531**
this morning by `f444a4a33` (*"the exposure is 531 stdout-only rows"*).

Counted at each commit that touched the Makefile since:

| sha | lane | stdout-only | delta |
| --- | --- | --- | --- |
| `f444a4a33` | T (armed here) | 531 | — |
| `8b85e4881` | **P** — the bound-name harvest | 544 | **+13** |
| `df690b519` | **A+S** — SPECIAL_IN in both 32-bit cross backends | 548 | **+4** |
| `df8731b1f` | **O** — -O3 aarch64 fuses the resident read | 550 | **+2** |
| `6ef921b4e` | **O** — -O3 aarch64 collapses the last push/pop | 551 | **+1** |

Four commits, three lanes, six hours. **The ratchet is working** — this is the
success case, not a stale number: it caught a 20-row drift within hours of being
armed, and the drift is attributable because it was armed at all.

## Why the rows matter

A cross-target differential row runs the same program natively and on a cross
target and compares **stdout**. It does not compare the exit status. So a
program that `Halt(5)`s on one target and exits 0 on the other, with identical
output, **passes**. That is not hypothetical — it is the exact shape frankS's
xtensa bug lived in, and it is why the family guard in section 1 exists at all.

The fix is mechanical and free: both sides are runs of the same program, so
appending `; echo "exit=$$?"` inside each capture costs nothing and closes it.
20 rows, in the four commits above.

## What this ticket does NOT ask for

Not the other 531. That number is a standing exposure with its own history, and
closing it is a separate, much larger call. This ticket is the **20 that landed
after the line was drawn**, because those are the ones whose authors are known,
whose diffs are small, and who can fix them for the cost of a `sed`.

## The gate cost, stated rather than absorbed

`tools-devtest` is enrolled in the **limited** and **full** tiers (not quick,
not native). So this red does not touch any lane's per-fix loop, and it does not
block a push — but it is red in every watcher sweep until it lands, and it will
keep auto-filing.

**Do not resolve this by bumping the ratchet.** A high-water mark that is raised
whenever it is reached measures nothing; it is the same move as widening a
tolerance until the guard stops complaining, which
`chore-a-re-include-bench-timing-in-tools-devtest` is the cautionary tale for.
If the standing red is judged too expensive to hold while the rows are fixed,
the honest alternative is to make section 3 **report the drift and its
attribution without failing** — its own docstring says its job is that the
number "cannot drift upward unnoticed", and noticing does not require a gate
failure. That is a Track U call about what a shared gate should do when the
number it watches grows as a side effect of other lanes' normal work; it is not
something to settle by editing the constant.

## Resolution (2026-08-30, frank-optimize-b4)

**28 rows, not 20** — eight more landed between the ticket being filed and being
picked up (the ratchet read **559**, not the 551 in the table above). The count
is back to **531** and `tools/exit_observable_devtest.py` is **9 guards, 0 FAIL**.

The set was derived rather than eyeballed: extract every cross-target
differential row (`run_target.sh` + two `"$$(` captures + no `exit=$$?`) from
`f444a4a33:Makefile` and from HEAD, sort, `comm -13`. 28 new, **0 gone** — so
nothing was lost from the armed set on the way, which is worth knowing before
trusting a delta.

### Three shapes, not one, and the difference is the whole job

| shape | count | edit |
| --- | ---: | --- |
| cross run vs native run of the same program | 21 | `; echo "exit=$$?"` on both sides |
| cross run vs a `printf` literal | 6 | capture on the run side, `\nexit=0` appended to the literal |
| cross run **piped through a filter** | 1 | see below — the append is WRONG here |

**`xtensa/test_rtti` is the one that could not take the mechanical edit.** Both
sides pipe the program through `grep -vE` to strip addresses, and `$?` after a
pipeline is the LAST command's status — appending the capture there would have
asserted that **grep ran**, which is precisely the "anything appended after the
thing you are measuring becomes the thing that reports" defect this whole check
exists to catch. Writing that would have been the bug wearing the fix's clothes.
It now redirects the run to a file, echoes the status while the run is still the
last command, and filters the file afterwards; the status line therefore comes
**first** on that row, and both sides are built identically so the comparison is
unaffected.

### The two rows the verification caught, which is why it was run

`xtensa/test_readln` and `xtensa/test_eof_stdin` look like the literal shape and
are not:

```make
"$$(printf 'alpha\nbeta\ngamma' | tools/run_target.sh xtensa $(BIN))" "$$(printf 'alpha\nbeta\ngamma' | $(BIN)_x64)"
```

The right-hand `printf` is not an expected value — it is **stdin for a second
run of the same program**. The mechanical rule "append `\nexit=0` to the printf"
appended it to the *input data*, feeding both a corrupted stdin. Both rows went
red immediately, with a diff showing `exit=0` present in actual and absent in
expected. They are now the run-vs-run shape, with the capture on both sides and
the stdin literals restored.

**That is a classifier bug in my edit, found by running the rows rather than by
reading them**, and it is the exact hazard this ticket's sibling warns about: the
strengthening is free *in principle* because both operands are runs of the same
program, and these two rows are the case where that premise is false on one side.

### Verified by execution, not by the ratchet going green

The ratchet counts a string; it cannot tell a correct capture from a corrupting
one. So all **33** rows that now carry a capture (the 28 new plus the 5 that
already complied — the pre-existing ones included deliberately, as the control
that the harness can pass) were extracted with their preceding build lines into
a scratch makefile and run: `make -k` **exit 0**, no `MISMATCH`, across xtensa,
riscv32, aarch64, arm32 and i386.

**No exit-code disagreement was found on any of the 28.** frankS's measurement
that `run_target.sh` returns the EMULATOR's status, and that signal deaths do
not encode identically under qemu-user and a native shell, predicts diffs on
rows whose subject dies by signal — and none of these 28 does. That is a result
about this set, not a refutation of the caution, and it is exactly why the
sibling campaign over the other 531 still wants piloting one arch at a time.

### One finding for Track T, not acted on here

`exit_observable_devtest.py` matches the literal string `exit=$$?`. For a
**filtered** subject the only correct form captures the status before the pipe,
and the natural spelling (`e=$$?` … `echo "exit=$$e"`) does not contain that
literal, so a correct row reads as non-compliant. I avoided it by ordering the
status first — which is fine, and slightly clearer — but the checker cannot
currently express the general case, and a future filtered row will hit the same
wall. **T's file, T's call**; noting it rather than editing it.

### Not done, deliberately

The other 531. Not bumping the ratchet, which this ticket explicitly forbids and
is right to.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
