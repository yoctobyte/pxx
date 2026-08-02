---
summary: "The --threadsafe self-compile needs 65657 global fixups against a fixed cap of 65536 — over by 121. A GATED test-core job is red on master, and `make compiler/pascal26` is green, so the normal build masks it completely"
type: regression
track: A
prio: 75
status: done
---

# `--threadsafe` self-host is 121 fixups over `MAX_GLOBFIX`

- **Type:** regression, gated — **Track A** (`compiler/defs.inc`,
  `compiler/emit.inc`)
- **Filed:** 2026-08-02 by `claude@xeon` (Track T) from the `test-core` matrix.
  **T owns the tool, never the bug** — measured and handed over, not fixed.
- **Reproduces at HEAD** (`07e4f8424`). This is live, not a stale callback.

## Repro — one command, ~15s

```
$ ./compiler/pascal26 --threadsafe compiler/compiler.pas /tmp/ts-self26
pascal26:135867: error: global fixup overflow
```

## Measured

Instrumented `GlobFixCount` at output time and raised `MAX_GLOBFIX` to 393216
temporarily to see the real requirement (both edits reverted; the tree this was
filed from is clean and rebuilt at HEAD):

| build | global fixups | cap | headroom |
|---|---|---|---|
| normal self-compile | **45326** | 65536 | 31% free |
| **`--threadsafe` self-compile** | **65657** | 65536 | **-121, overflows** |

Threadsafe costs **+20331 fixups (+45%)** over the normal build — consistent
with thread-local access emitting an extra global fixup per reference. The
overflow is by **0.18%**. It has been walking up to this line for some time and
just crossed it.

## Why it looks fixed and is not

`make compiler/pascal26` — the byte-identical fixedpoint every dev track gates
on — is **GREEN**, because it does not pass `--threadsafe` and sits at 45326.
The failing recipe is the second self-host chain inside `test-core`:

```make
./$(COMPILER) $(PXXFLAGS) --threadsafe $(COMPILER_SRC) /tmp/pascal26-threadsafe-self
/tmp/pascal26-threadsafe-self $(PXXFLAGS) --threadsafe $(COMPILER_SRC) /tmp/pascal26-threadsafe-next
cmp /tmp/pascal26-threadsafe-self /tmp/pascal26-threadsafe-next
```

So the normal fixedpoint masks it entirely, and the job is `test-core`, which
**gates** (unlike the advisory FPC canary). A dev following the documented
"green quick + push" loop cannot see this.

## Do not bisect for a culprit

The watcher's range names `e53fa4a3f` as the only `compiler/**` commit between
the last green (`65c53ad280bc`) and the red (`96cffaf08de5`). That is true and
almost beside the point: at **121 over a 65536 cap**, whichever commit happened
to add the last few globals gets the blame, and reverting it only buys back a
handful of entries before the next feature re-crosses. Treat it as a capacity
bug, not a bad commit.

## Fix directions

1. **Raise `MAX_GLOBFIX`.** `GlobFix: array[0..MAX_GLOBFIX-1] of TGlobFix` is
   static, and the measurement gives its cost exactly: raising the cap by
   327680 entries grew BSS by 5242880 B, i.e. **16 bytes per entry**. Doubling
   to 131072 therefore costs ~1 MB of BSS reservation — and BSS is reserved,
   not resident (only touched pages land in RSS; that is why `hello.pas` runs
   in 24 MB against a 151 MB `bss=`). Cheapest fix by a distance.
2. **Grow it dynamically.** Correct, and removes the whole class — but it is a
   hot table in the emitter and the allocation path is exactly where this
   compiler has historically been slow.
3. **Dedupe fixups.** 65657 entries for 2379 procs suggests repeats; if the
   same (symbol, addend) recurs, collapsing them attacks the growth rather
   than the ceiling. Needs a look at what threadsafe actually emits — the +45%
   is suspicious on its own and may be a bug rather than a cost.

Recommendation: **1 now** (it unblocks a gated job today for ~1 MB of
reservation), then **3** as the real question — *why does threadsafe need 45%
more global fixups?* is worth answering separately, because if it is
one-per-TLS-access there may be a cheap win in the emitter.

## Gate

`./compiler/pascal26 --threadsafe compiler/compiler.pas /tmp/x` compiles clean,
the `test-core` threadsafe chain reaches its `cmp` and matches byte for byte,
and the normal fixedpoint stays byte-identical.


## Resolved 2026-08-02 — commit 91f063250 (fix direction 1, as recommended)

Found independently from the same tstate NEW-RED about an hour before this
ticket was read, and fixed the same way — which is a small vote of confidence in
the measurement: two paths reached "capacity limit, not bad commit".

`MAX_GLOBFIX` 65536 -> **262144** (~4x headroom against the threadsafe build's
65657), with the *reason* recorded at the constant, including this ticket's
numbers and the "16 bytes per slot, reserved not resident" note. The next person
to add a global to the compiler should not have to rediscover why the last unit
suddenly fails to emit.

Verified against this ticket's own gate:

- `./compiler/pascal26 --threadsafe compiler/compiler.pas` compiles clean
- the `test-core` threadsafe chain reaches its `cmp` and matches byte for byte
  (re-run as `testmgr --tier native --job 'test-core#*'` -> GREEN)
- the normal fixedpoint stays byte-identical (`gate.sh quick` GREEN)

**Fix direction 3 is NOT done and is the interesting part** — *why* does
threadsafe need 45% more fixups for the same source? Split out as
[[feature-a-why-threadsafe-needs-45pct-more-global-fixups]] at prio 35 so it
survives the closing of this ticket. Direction 2 (dynamic growth) is deliberately
not taken: it puts an allocation on the emitter's hot path for a table that is
now 4x oversized.

One correction to the record: the commit message for 91f063250 says 8 bytes per
slot, reasoning from `TGlobFix`'s two Integers. This ticket MEASURED 16. The
constant's comment carries the measured figure.

## Log
- 2026-08-02 — resolved, commit 91f063250.
