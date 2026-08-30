---
slug: bug-p-a-specialized-body-reports-errors-in-the-wrong-file
track: P
prio: 60
type: bug
status: backlog
blocked-by: []
summary: "An error inside a replayed (specialized) generic method body reports a file and line that are BOTH wrong — measured on the rtl-generics corpus, where `unknown type: TKey` is attributed to `generics.defaults.pas:78` while its own `near:` context is `generics.collections.pas:1631`, another unit ~1550 lines further down. `TKey` does not occur in the named file at all. Only `near:` survives substitution, so `near:` is currently the only trustworthy field. Not a parity issue with FPC — our own diagnostic points at the wrong source — and it costs real time on every corpus triage, because the first move is always to open the named file."
owner: unassigned
---

# A specialized body reports its errors in the wrong file (and the wrong line)

Found while re-measuring the corpus after
[[bug-p-a-cross-unit-specialization-streams-method-bodies-into-the-interface]].
Not that bug, and not blocking it — this is about where errors *say* they are.

## Measured

Probe: `pascal26 -dVER3_0_0 -Fu<rtl-generics/src> gcprobe.pas`, binary
`d5a35c8de13a`.

```
pascal26:78: error: unknown type: TKey
  in: .../rtl-generics/src/generics.defaults.pas
  near: ) * SizeOf ( T ) >>> ) ; FillChar
pascal26:79: error: unknown type: TKey
  in: .../rtl-generics/src/generics.defaults.pas
  near: [ ANewIndex ] , SizeOf ( >>> T ) ,
```

Three independent checks say the location is wrong:

- **`TKey` does not occur in `generics.defaults.pas`.** `grep -n TKey` on that
  file returns nothing. The identifier the error names is not in the file the
  error names.
- **The `near:` text is in a different unit.** `ACount * SizeOf(T), #0)` followed
  by `FillChar` is `generics.collections.pas:1631` / `:1635`; the second error's
  `[ANewIndex], SizeOf(T)` is `generics.collections.pas:1687`. Both sit in
  `TList<T>` method bodies.
- **The lines are not the sites either.** `generics.defaults.pas:78-79` is the
  `IEqualityComparer<T>` interface declaration — no `FillChar`, no `SizeOf`.

So a token replayed out of a buffered template carries stale position
information, and the reporter trusts it. `near:` is reconstructed from the
tokens themselves, which is why it alone stayed honest.

## Why it is worth a ticket even though it is "only" a diagnostic

The taxonomy in CLAUDE.md defers *parity* of diagnostics — ours differing from
FPC's. This is not that. This is our diagnostic naming a file that does not
contain the problem, which sends every triage to the wrong unit first. The
corpus is the oracle for Track P's generic work; an oracle whose failures point
somewhere else is expensive in exactly the lane that reads it most.

## Open, NOT diagnosed — do not assume it is one bug

At the same wall, `unknown type: TKey` is raised while the surrounding token run
still shows `SizeOf(T)` with `T` **un-substituted**, and `TKey` is not a
parameter of `TList<T>` at all. That looks like a body being replayed against a
different template's parameter set — a separate mechanism from stale positions.
It is a hypothesis, not a finding; it has not been reproduced in isolation.
Reduce it to a small case before writing a cause into this ticket. Filed
separately as
[[bug-p-the-rtl-generics-corpus-stops-on-tkey-in-a-tlist-body]].

## Independently found twice, from two different corpora — merged, and raised 40 -> 60

Filed within minutes of each other by **frank-rust** (this ticket, from the
rtl-generics probe) and by **frankB** (from rung 6b of
[[feature-pascal-corpus-expansion]]), neither having seen the other. The duplicate
`bug-p-a-deferred-generic-body-s-diagnostic-names-the-wrong-file-and-line` is
closed into this one; its evidence is folded in below. **Two independent
observations from different source files strengthen this considerably** — it is
not one probe's quirk.

### frankB's instance, HEAD `4f42b78b9` / pinned `faf762981c3c`

```
unknown type: TKey
in: generics.defaults.pas   line 78
near: ) * SizeOf ( T ) >>> ) ; FillChar
```

| claim | check |
| --- | --- |
| the error is in `generics.defaults.pas` | `TKey` occurs **zero** times there, **65** times in `generics.collections.pas` |
| …at line 78 | `defaults.pas:78` is `function Equals(constref ALeft, ARight: T): Boolean;` — no `TKey`, no `SizeOf` |
| the `near:` context | matches `generics.collections.pas:1309-1310` |

frank-rust's instance names the same wrong file with `near:` pointing at
`generics.collections.pas:1631` — a different line ~320 rows away, so the two are
separate reproductions rather than one error seen twice.

**In both: only `near:` survives substitution.** The file attribution and the line
number are both wrong; the token context is right. That is the signature to fix
against, and it is what makes the bug detectable at all.

### Why p60 rather than the low-prio error-reporting default

CLAUDE.md defers *parity* of diagnostics — "our message differs from FPC's" — as
low prio. **This is not parity.** The diagnostic is not differently worded, it is
**false**: it names a file that does not contain the symbol. It misroutes triage
rather than merely reading differently, and it does so on the exact path the p75
corpus campaign runs, in the lane that reads the corpus most. It cost frankB a
pass and frank-rust a detour on the same afternoon.

### Gate

A test whose expected output names the **instantiating** file. Assert the file
attribution, not merely that an error occurs — an error occurring is what happens
today.
