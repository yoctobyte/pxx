---
slug: feature-a-pull-builtinheap-on-demand-instead-of-predicting-it
title: "Pull builtinheap at first reference instead of predicting it from a token pre-scan"
track: A
prio: 40
type: feature
blocked-by: []
status: backlog
owner: ""
created: 2026-09-22
summary: "The Pascal driver decides whether a program needs `builtinheap` by a TOKEN PRE-SCAN, but the need is only discovered during parsing and codegen, so the scan is a prediction that is structurally always behind. FIVE triggers had to be added by hand on 2026-09-22 to get it to zero regressions (WideChar/PChar/UCS4Char, __pxxHwRandom64, Assert under --esp-profile=bare, `writeln(x:0:0)`, `{$Q+}`) and there is no argument that the fifth is the last -- two of them were found only by a 2312-file compile-only differential, not by reading. THE COST OF BEING WRONG IS BOUNDED AND THAT IS WHY THE SCAN SHIPPED: under-detection is a loud compile-time abort naming a PXXStr* symbol, never a miscompile (measured 36 of 36 across six string shapes by six targets), and over-detection costs only size. So this is a FEATURE, not a bug -- nothing is broken today. WHAT WOULD RETIRE IT: pulling builtinheap at the first reference to one of its helpers instead of predicting. Demonstrably possible -- pasparser_proc.inc:7057 already calls ParseUsesUnitAmbient('builtinheap') mid-parse on the C path -- and NOT free: that same site records in its own comment that a nested unit load overwrites the global UnitContent, which once made the compiler preprocess pxxcio.pas as if it were the C file, with no diagnostic anywhere near the cause. Anyone taking this must handle that global-state hazard first. Deciding the ORDER is the real work; the flag union itself is one line."
---

# The scan is a prediction of something only codegen knows

`DetectPascalRuntimeNeeds` walks the token array and guesses which runtime
units the program will need. The guess is consumed at
`pasparser_prog.inc:1412` (`needHeapUnit`) and again at the emission site
~600 lines later. But whether `builtinheap` is actually needed is decided by
what the parser and the backends **emit**, which happens after both.

The gap is not theoretical and it is not small. Getting the evidence-based
scan to zero regressions on 2026-09-22 took five separate triggers:

| trigger | helper it needs | how it was found |
| --- | --- | --- |
| `var v: WideChar` / `PChar` / `UCS4Char` | `PXXStrFromLit` | reported by the park |
| `if __pxxHwRandom64(v)` | `PXXStrFromLit` | grepping for the sibling |
| `Assert` + `--esp-profile=bare` | `PXXStrDecRef` | grepping for the sibling |
| `writeln(x:0:0)` | `PXXWriteFloatFixed` | corpus differential |
| `{$Q+}` arithmetic | `PXXOverflow` | corpus differential |

**Two of the five were invisible to reading.** They came from compiling all
2312 `test/*.pas` under both compilers and diffing which ones built. The
`writeln(x:0:0)` row contains no float literal and no `/`, so neither the
`tkFloat` nor the `tkSlash` arm of the scan can see it; `{$Q+}` is not a token
at all, it is per-token state in `TokQChecks`.

**There is no argument that the fifth is the last**, and the shape of the
search says so: every pass found more, and the last pass found them with an
instrument nobody had pointed at this before.

## Why this is a feature and not a bug

Nothing is broken at HEAD. The cost of the scan being wrong is bounded in the
direction that matters:

- **Under-detection is a loud compile-time abort** naming a `PXXStr*` symbol —
  never a wrong answer at run time. Measured over six string shapes by six
  targets: 36 of 36 refused, 0 built.
- **Over-detection costs size only.**

That asymmetry is the entire reason a prediction was allowed to ship. It is
also why this ticket is p40 and not higher: the next missing trigger will
announce itself as a build break with the symbol in the message, and it is one
line to add.

## What would retire it

Pull `builtinheap` at the **first reference** to one of its helpers rather
than predicting. The registration block already enumerates exactly which
helpers those are, so the set is known and closed — the question is ordering,
not identification.

**It is demonstrably possible.** `pasparser_proc.inc:7057` already calls
`ParseUsesUnitAmbient('builtinheap')` from inside proc parsing, on the path
where a `uses <cheader>` pulls in the C frontend. So a mid-parse pull is not
a new capability.

**It is not free, and the hazard is recorded at that very site.** Its comment
says `UnitContent` is a GLOBAL holding the source about to be preprocessed,
and that a nested unit load overwrites it with ITS source — the first cut of
that pull left it unsaved, so from there on the compiler preprocessed
`pxxcio.pas` as if it were the C file, every declaration in the real header
vanished, and `uses <someheader>` reported the header's own functions as
undefined variables **with no diagnostic pointing anywhere near the cause**.
It took a regression in `examples/life`'s GTK binding to find.

So whoever takes this: the global-state hazard is the work, not the pull.

## Do not

Do not "fix" a future missing trigger by widening the `needHeapUnit` union
until everything passes. That reintroduces the 63,760-byte hello-world
[[bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce]] removed.
`test/pascal_ambient_unit_needs_heap.sh` asserts both directions for exactly
this reason and will redden on that repair.
