---
slug: decide-adopt-a-second-string-model-or-refuse-utf16-honestly
title: "UnicodeString/WideChar: adopt a second string model, or refuse UTF-16 honestly and document it?"
track: U
prio: 62
type: decide
blocked-by: []
status: backlog
owner: ""
created: 2026-08-30
found-by: frank-coordinator, escalating feature-unicodestring-model rather than dispatching it
summary: "feature-unicodestring-model [A p62] says in its own body that this is a MODEL DECISION, not a function to write -- and its title offers the alternative outright: a real UTF-16 model, or an honest refusal. pxx has one string model (bytes, CP_UTF8 passthrough) and the RTL is already candid about it at the declaration: UTF8Decode/UTF8Encode are the identity, WideChar casts to a 2-byte ordinal. Adopting UTF-16 is a second model in a compiler whose whole design pushes generality DOWN into one substrate. Refusing means fcl-json's \\uXXXX surrogate path stays uncompilable. Neither is derivable from the code or from a sensible default, so it is Track U."
---

# Why this is being escalated rather than worked

`feature-unicodestring-model` is ranked p62 and reads like implementation work. It
is not. Its own body says *"Why this is a model decision, not a function"*, and its
title already carries both branches: **a real UnicodeString / WideChar model
(UTF-16), or an honest refusal.** Dispatching it would mean an agent picking one,
and that choice constrains the language permanently.

## The wall, unchanged since 2026-07-13

`jsonscanner.pp` decodes a `\uXXXX` escape and, for a surrogate pair, does:

```pascal
S := Utf8Encode(WideString(WideChar(u1) + WideChar(u2)));
```

`WideChar(x) + WideChar(y)` is a two-element UTF-16 string. pxx has ONE string
model — bytes — so `WideChar` is a 2-byte ordinal, `+` is integer addition, and
`String(...)` of the result is rejected. **The rejection is correct**; there is
nothing to silently do instead.

## The fork

| option | cost | buys |
| --- | --- | --- |
| **A. Adopt a real UTF-16 model** | a SECOND string model in a compiler whose north star (`ir-as-substrate.md`) is pushing generality down into one substrate. Every backend, every managed-string path, the `PXXStrUnique`/frozen-vs-ansistring split, and the sibling-arm rule that has bitten three times today all get a second arm | `fcl-json`'s `jsonscanner`/`jsonparser` compile; genuine FPC/Delphi source compatibility for `WideChar`/`WideString` code |
| **B. Refuse honestly, document, and move on** | `fcl-json`'s `\uXXXX` surrogate path stays uncompilable, so that corpus item stays out of reach. `fpjson` itself is DONE and unaffected | one string model stays one string model. Consistent with the RTL already being candid at the declaration — `UTF8Decode`/`UTF8Encode` are the identity, `DefaultSystemCodePage` reports `CP_UTF8` because the bytes really do pass through |
| **C. A narrow escape hatch** — a surrogate-pair decoder that produces UTF-8 bytes directly, without a UTF-16 string TYPE | it is a special case, and `normalise-dont-special-case.md` is the note that says the second path is the one that stays broken | unblocks the concrete corpus item without a second model |

## Recommendation

**C, with B as the stated position** — but this is the owner's call and I hold it
weakly.

The compat table in CLAUDE.md is the relevant instrument: *"FPC accepts a form we
reject" → compat, ranked by how much real code uses it.* `WideChar` arithmetic
building a UTF-16 string is not a form much real Pascal reaches for; the specific
thing that wants it is JSON `\uXXXX` decoding, which is a byte-output problem
wearing a UTF-16 hat. So the concrete need can be met without the model, and the
model can stay one.

Against my own recommendation: C is a special case by construction, and this repo
has spent the day proving that special cases are where the rot lives. If the owner
expects real FPC/Delphi corpora to keep arriving with `WideString` in them, A is
the honest answer and the cost should be paid deliberately rather than deferred
one corpus item at a time.

## Why now

frankwasm asked for this ticket, having just finished the wasm string lowering —
`IR_LEA` position dependence, the managed-store path, `PXXStrUnique`, the
frozen-vs-ansistring split — and that context is exactly what option A would
need and is stale within a day. If A is ever going to be chosen, choosing it while
a lane is warm on the string paths is materially cheaper than choosing it later.
That is a scheduling argument, not an argument for A.
