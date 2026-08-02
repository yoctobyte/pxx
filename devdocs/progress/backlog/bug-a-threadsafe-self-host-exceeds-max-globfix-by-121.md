---
summary: "The --threadsafe self-compile needs 65657 global fixups against a fixed cap of 65536 — over by 121. A GATED test-core job is red on master, and `make compiler/pascal26` is green, so the normal build masks it completely"
type: regression
track: A
prio: 75
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
