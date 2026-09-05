---
track: D
prio: 45
type: bug
blocked-by: []
summary: "`tools/docsnip.py` compiles docs/** snippets against the PINNED compiler, and three of them now fail with `unknown type: TMethod` — inside lib/rtl, not inside the snippet. `a623307bd` made TMethod a builtin and deleted the RTL duplicates, so the pin's compiler cannot build the current RTL at all. Nothing is wrong with the three documents; Track D's only gate is red for every session until the next pin."
---

# The docs snippet gate cannot pass: the pin predates `TMethod` becoming a builtin

```
$ python3 tools/docsnip.py
docsnip: 200 code blocks, 39 complete Pascal programs, 161 fragments/other
  compiled or failed-as-documented: 30   BROKEN: 3   skipped: 6
  BROKEN  docs/library/json.md:49         pascal26:413: error: unknown type: TMethod
  BROKEN  docs/library/networking.md:13   pascal26:413: error: unknown type: TMethod
  BROKEN  docs/library/networking.md:92   pascal26:413: error: unknown type: TMethod
```

`pascal26:413` is a line in a **library unit**, not in any snippet.

## The three documents are fine

Extracted `docs/library/networking.md:13` verbatim and compiled it both ways at
`9bcfd2b4da30`:

| | result |
|---|---|
| HEAD | `ok: … [code=1351448B …]` |
| `stable_linux_amd64/default/pinned` | `near: m : TMethod ; begin m >>> . Code :=` |

`a623307bd` — *"System.TMethod is declared once — delete the RTL duplicates, and
let a UNIT see the builtin"* — moved `TMethod` into the compiler and removed the
declarations `lib/rtl` used to carry. The pinned compiler has no builtin
`TMethod` and the RTL no longer declares one, so **the pin cannot build the
current RTL**, and every snippet that reaches it fails.

## Why this is worth a ticket and not a shrug

**A gate that cannot pass is not a gate.** Track D's gate is "compile the
snippets against `$(PXX_STABLE)`" and it is the only one D has. Red for a reason
no doc change can fix means the next D session either reads three permanent reds
as background noise — and then misses a real fourth — or spends the same
half-hour re-deriving this.

It is also the mirror of the trap `$(PXX_STABLE)` guidance already warns about:
the known hazard is a snippet PASSING under the pin for a reason unrelated to
the change. This is the same mechanism pointing the other way, and it is louder,
so it is the easier half to catch — but only once.

## Options, none of them Track D's to pick

1. **A new pin** picks it up for free. Track A, blocks everyone while it runs,
   and there is a green-vs-reds grading question that is not mine.
2. **`docsnip.py --head`** — an opt-in arm for exactly this window, red-flagged
   in its own output so nobody quietly makes it the default. Track T owns the
   tool.
3. **Leave it and record the three** so a fourth is visible. Cheapest, and what
   this ticket does in the meantime.

Found 2026-09-05 by frankD (Track D) while gating the `{$MODE}` dialect-scope
doc update — which added no snippets, deliberately, because the pin cannot
demonstrate the behaviour being documented either.
