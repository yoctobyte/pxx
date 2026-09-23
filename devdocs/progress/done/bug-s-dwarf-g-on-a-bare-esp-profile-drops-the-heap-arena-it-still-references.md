---
slug: bug-s-dwarf-g-on-a-bare-esp-profile-drops-the-heap-arena-it-still-references
track: A
type: bug
prio: 70
status: done
owner: frank
created: 2026-09-23
resolved: 2026-09-23
commit: 334aa5ec1
blocked-by: []
summary: "FIXED 2026-09-23. `-g` on a bare ESP profile refused with `internal: BSS offset 1264 is inside the dropped region [1264,66800) -- the drop predicate was wrong`, on BOTH ESP ISAs, so no bare-ESP program could be built with debug info. DropEspArenaIfAllocatorDead gated on `DceEnabled` -- the OPTION -- where the question is whether liveness was actually COMPUTED. DceRun opts out at runtime for six further reasons with the option still True, and `-g` is one of them (`line/frame tables carry code offsets`). DceLive is SetLength'd in symtab.inc beside every other per-proc array, so after an opt-out it is allocated, sized and ALL FALSE, which reads as `every proc is dead`: the predicate concluded HeapMmap's only reader was dead and punched out the 64 KiB arena, while DCE having not run meant HeapMmap's body was still emitted and still referenced it. The routine's own header asserted DceLive would be `an unallocated dynamic array` in that case -- which would at least have made its `procIdx >= Length(DceLive)` test fire -- and that was FALSE, so the one guard that could have caught this could never fire. Fix is a DceLiveValid flag, the native twin of the WasmDceActive that already existed in the same file."
---

# `-g` on a bare ESP profile drops the heap arena it still references

Found 2026-09-23 by reproducing the `test-debug-g` row Track T reported RED in
`20260923T205732Z-77eff69-borg.md`. T's earlier bisect had named
`04e20af2cfaa` ("drop the 64 KiB bare-ESP heap arena when DCE proves its only
reader dead") by adjacency, with no diagnosis; the adjacency was right.

## Reproduction

```
$ pascal26 -g --target=xtensa --platform=esp --esp-profile=bare dbgsmoke.pas out
pascal26:1: error: internal: BSS offset 1264 is inside the dropped region
                   [1264,66800) -- the drop predicate was wrong
```

`66800 - 1264 = 65536` — the arena exactly, and the offending offset is its
first byte. Both axes are required and **both ESP ISAs fail**, so this was never
xtensa-specific:

| | default | `-g` | `-g --no-dce` |
| --- | --- | --- | --- |
| xtensa bare | ok | **refused** | ok |
| riscv32 bare | ok | **refused** | ok |

## Mechanism

`DropEspArenaIfAllocatorDead` asks *"is HeapMmap live"* via `DceLive`, gated on
`DceEnabled`. Two things make that wrong together:

1. **`DceEnabled` is the option, not the outcome.** `DceRun` opts out at
   *runtime* for six further reasons with the option still True — `--shared`,
   an unwired frontend, an `.asm` entry override, and `-g`, whose stated reason
   is *"line/frame tables carry code offsets"*.
2. **`DceLive` is allocated even when the pass never runs.** `symtab.inc`
   `SetLength`s it beside every other per-proc array, so after an opt-out it is
   sized and **all False** — which reads as *"every proc is dead"*.

So under `-g`: DCE turns itself off, the predicate reads the all-False array,
concludes the arena's only reader is dead, and punches out 64 KiB — while the
same opt-out means `HeapMmap`'s body is still emitted and still references it.
`BssRemap` then refuses the live reference into the dropped region.

**The guard that should have caught this could never fire.** The routine's
header claimed `DceLive` would be *"an unallocated dynamic array"* when the pass
does not run, and the predicate duly tests `procIdx >= Length(DceLive)`. That
length test only ever fires on an unsized array, which does not happen — so a
comment that was wrong about the mechanism produced a guard that was decorative.
`BssRemap`, by contrast, did exactly what its own header promised: refused
loudly and named this predicate, rather than clamping to a neighbouring variable
and producing the plausible-wrong-value failure.

## Fix

`DceLiveValid` — the native twin of `WasmDceActive`, which already existed in
the same file for the same purpose. Set False at the top of `DceRun` *before*
the option test, so every opt-out path leaves it False, and True once marking is
complete and `DceLive` is authoritative. The arena predicate gates on it
instead of on `DceEnabled`. The stale claim in the header is corrected rather
than deleted, since it is the reason the guard looked adequate.

## Controls — the size win is intact, which is the thing a "fix" could quietly cost

The predicate's own header names `--no-dce` as its positive control. Measured on
the dwarf smoke program, xtensa bare:

| build | bss | arena |
| --- | --- | --- |
| default | 1,304 B | dropped |
| `--no-dce` | 66,840 B | kept |
| `-g` (was: refused) | 66,824 B | kept |

66,840 − 1,304 = 65,536 exactly. So the drop still happens where it should, and
the fix only stops it happening where liveness was never computed.

`tools/dwarf_smoke.sh` OK, `make test-debug-g` GREEN, `gate.sh quick` GREEN,
fixedpoint converged.

## Not closed by this

`regression-test-debug-g-compiler-srchash-2` (auto-filed 2026-09-06) names the
same JOB but its recorded failure is **step 1/2**, the `livesrc`/`stampsrc`
comparison — a different step from the dwarf-g arm fixed here. The full target
is green at HEAD, but attributing that to this fix would be a guess, so it is
left open for whoever can say what it was.

# Umbrella

[[meta-a-pxx-produces-linkable-code]]
