---
prio: 30
---

# Track D: fpc-compatibility.md understates the language aim ("useful subset")

- **Track:** D (docs — `docs/language/fpc-compatibility.md`)
- **Found:** 2026-07-15, wiring the doc into the website's Compliance section
  (Track W). The opening framing is wrong about intent.

## The problem

`docs/language/fpc-compatibility.md` opens with:

> PXX aims to compile a useful FPC/Object Pascal-like subset. It does not claim
> full FPC language, RTL, package, object-file, or command-line compatibility.

That lumps the **language** in with the toolchain surface and says we aim at a
"subset". Per the project's actual intent, that's wrong on the language axis:

- pxx **does** aim at **full FPC-language compatibility** — the Object Pascal
  language as FPC accepts it (the conformance suite is run precisely to chase
  this; see the `compat` tag in the agent guide).
- What pxx deliberately does **not** target is the rest of FPC's world: the
  **RTL / package ecosystem**, the **object-file format**, and the **command-line
  interface**.

So the split is "full language, yes; toolchain + library surface, no" — not
"useful subset of everything".

## Suggested fix

Reword the opening, e.g.:

> PXX targets **full FPC-language compatibility** — the Object Pascal language as
> Free Pascal accepts it. It does **not** aim at parity with the rest of FPC's
> world: the FPC RTL and package ecosystem, the object-file format, or the
> command-line interface are out of scope by design.

The "Important differences" section lower down already lists the RTL/package/CLI
carve-outs correctly — only the intro's language framing needs fixing.

## Note

The website (Track W) already leads its FPC-compatibility page with the corrected
framing, but it still renders this doc verbatim below, so the stale sentence is
publicly visible until this is fixed.
