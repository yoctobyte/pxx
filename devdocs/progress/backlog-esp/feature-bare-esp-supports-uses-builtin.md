
## 2026-09-24 (frank, frankb-8e) — re-measured at HEAD, and the mechanism named exactly

The chain data above is from 2026-08-30 and its LINE NUMBERS have moved
(`PXXVarBinOp` is now `builtin.pas:1355`, was 1148). The behaviour has not. What
follows is measured at HEAD, riscv32 and xtensa, in a scratch probe.

**Still step 0, still identical on both ISAs, line for line** — so the ticket's
"profile property, not an ISA one" claim holds unchanged:

```
pascal26:1355: error: undefined variable (PXXVarBinOp)
  in: ./compiler/builtin/builtin.pas
```

**THE PROBING METHOD ABOVE IS CORRECT, AND CLAUDE.md APPEARS TO CONTRADICT IT
WITHOUT DOING SO** — worth stating because a seat that reads both will stop.
CLAUDE.md warns that a relocated binary finds no builtin beside itself and falls
through to a CWD-relative last resort, which silently picks up a sibling
checkout. Both are true about different layouts: `--where` at the repo root
reports the builtin root as `<exedir>/builtin/`, so a scratch dir works **only
if `builtin` is copied next to the binary**, which is exactly what this ticket
says to do. Mirror the repo — `pr/compiler/{pascal26,builtin}` plus `pr/lib` —
and `--where` shows every root resolving. Check `--where` rather than assuming;
with `lib` merely symlinked, the RTL roots print `[MISSING]` and the failure
looks like a compiler bug.

**And a symlinked `lib` is a live hazard in that probe**: edits through it land
in the repo. Guard edits belong in the `builtin` COPY.

## Why pulling the unit explicitly does not help, which nobody had recorded

The obvious first move is `uses builtinheap, builtin;`. **Measured: identical
error.** `PXXVarBinOp` and `PxxSciDigits17` are declared inside
`{$ifndef PXX_ESP}` in `builtinheap.pas` (around :583 and :597), and
`builtinheap.pas` opens with `{$ifdef PXX_ESP_BARE}{$define PXX_ESP}{$endif}`.
So on bare the declarations are **not in the unit at all** — this is not a link
or search-path problem and no `uses`, `-Fu` or unit ordering can reach it. The
`espassert.pas` header already records the same two names as the reason that unit
exists separately; this is that note's mechanism.

## The surface the cascade would have to cover, sized

The ticket calls the cascade open-ended, and it is, but the SIZE is measurable
and had not been measured:

- `builtin.pas` is **2863 lines, 251 top-level routines**.
- **12 are the Variant group**, and they sit in two near-contiguous regions —
  declarations `:143`–`:175`, bodies `:1131`–`~:1500` — not scattered.
- Float formatting (`FloatToStr`, `StrFloat`, the `PxxSciDigits17` caller near
  `:2029`) is the second group.

So it is roughly **two features, not two hundred call sites**, which is a
friendlier shape than "four steps deep and still going" suggests.

**But the cascade CHANGES CLASS after step 0, and that is why a declaration
census cannot size it.** Steps 1 and 2 above end in `__pxx_d2i_rne not linked`
and `__pxx_dcmp not linked` — LINK failures from float kernels, not undefined
declarations. A static intersection of "what builtinheap excludes" against "what
builtin.pas references" would answer confidently about the declaration class and
be silent about the link class, which is the shape CLAUDE.md warns about: a
census that cannot contain its subject. Do not build one and quote it.

## A principle that would make the remaining judgement calls mechanical

The ticket's real cost is that each step is an independent decision. One rule
collapses most of them, and the evidence for it is already in the tree:

> **On the bare profile, `builtin` offers no Variant support and no float
> FORMATTING.**

Float formatting first, because that argument is the strong one and it is
documented rather than aesthetic: **`writeln` is a no-op on bare** —
`docs/targets/esp32.md:70` says so, `espassert.pas` hand-rolls a UART write for
exactly that reason, and a draft of that unit *compiled and printed nothing*.
A profile with no console cannot be paying for 17-significant-digit decimal
conversion; that is dead weight by construction, not a trade-off. Variant
arithmetic on a flash-constrained part follows the same way.

Adopting that rule turns the cascade from "decide again at each step" into
"guard the two groups and keep going until it links", which is a bounded job with
a stated endpoint.

**NOT DONE HERE, and deliberately.** It is still a behaviour change to a unit
every program gets, the endpoint is unproven until something links, and the rule
above is a proposal with a name on it rather than a settled position — the sort
of thing that should be agreed before a seat spends an evening on it. What is
banked is the mechanism, the sizing, the corrected probing note, and the
principle.

**What would retire this ticket** is unchanged, plus one addition: a bare NilPy
program building AND running on a device, since on this profile `ok:` from the
compiler is not a result — that is `espassert.pas`'s own lesson and it applies
to every claim made here.
