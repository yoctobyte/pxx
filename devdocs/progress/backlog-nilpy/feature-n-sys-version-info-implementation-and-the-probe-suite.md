---
slug: feature-n-sys-version-info-implementation-and-the-probe-suite
track: N
prio: 62
type: feature
blocked-by: []
status: open
created: 2026-08-30
summary: "Implement sys.version_info / version / hexversion at (3, 9, 0, 'final', 0) plus sys.implementation carrying NilPy's own identity, per the owner's ruling. All four read ONE constant. The number is a compatibility affordance and must be backed by a probe suite that fails when it stops being true -- the same feature probes that produced the ruling."
---

# N: `sys.version_info` = 3.9, `sys.implementation` = nilpy, from one constant

Decided in
[[decide-nilpy-what-version-does-sys-version-info-claim]] (owner, 2026-08-30).
The ruling and the measurement behind it are there; this is the work.

## What to add

`sys.version_info` was never the identity field — PEP 421 put identity in
`sys.implementation`. Answering both is what lets NilPy report a usable language
level without claiming to be CPython. Both are absent today; both raise
AttributeError.

```
sys.version_info  = (3, 9, 0, 'final', 0)
sys.version       = '3.9.0 (NilPy <ver>)'
sys.hexversion    = 0x030900F0
sys.implementation.name    = 'nilpy'
sys.implementation.version = NilPy's own version tuple
```

**One constant, four readers.** The ticket that raised this said so and it is
the part most likely to be skipped: `version`, `hexversion` and `version_info`
disagreeing is a worse failure than any of them being wrong, because code that
cross-checks them is code that was already being careful.

## Where

- `compiler/pyparser.inc:11936` — `PyIsStdlibMemberValue`'s modelled-member
  list (`argv`, `platform`, `executable`, `stdout`, `stderr`, `stdin`). The new
  names join it; today they fall through to the qualified-spelling arm that
  raises at run time.
- `compiler/builtin/pylib.pas` — the `pysys_*` bodies, beside `pysys_argv`
  (:14958) and `pysys_executable` (:14966).
- `sys.implementation` needs an attribute-bearing value, not a scalar — check
  whether the modelled-member machinery can carry one before assuming the shape.
  This is the only part of the ticket that is not fifteen minutes.

## Also land, and they need no decision

`sys.maxsize` (`2**63 - 1` on the 64-bit targets — derive it, do not hardcode
across targets) and `sys.byteorder` (`'little'`). Flagged as independent by the
deciding ticket: they are plain facts about the target with no product claim
attached.

## The probe suite is part of this ticket, not a follow-up

The number is a **judgment call, not a derivation** — the measurement showed the
implemented subset is not an interval (gaps at 3.3 and 3.5 alongside features at
3.9), so nothing in the tree can compute it. That is exactly why it needs a test
underneath it: an asserted number rots silently, a tested one does not.

Ship the probes that produced the ruling as a NilPy test. Each is a few lines:

| must COMPILE and run | must be REFUSED (and the refusal is the assertion) |
| --- | --- |
| f-strings; `1_000_000` | `yield from` |
| f-string `=` specifier | `async def` |
| `@dataclass` | walrus `:=` |
| dict `\|` merge; `str.removeprefix` | positional-only `/` |
| `*` / `**` unpacking | `match`; `except*`; PEP 695 `def f[T]` |
| tuple comparison (`v >= (3, 7)`) | |

The right column is the load-bearing half and it is **not** a claim that those
features should stay unimplemented — it is a tripwire on the version claim. When
one starts compiling, the test fails, and whoever landed it has to decide
whether 3.9 is still the right number. That is the mechanism that stops the
claim drifting away from reality; without it the constant is someone's opinion
from 2026-08-30. See
[[bug-n-yield-from-is-not-implemented]] and
[[bug-n-async-def-and-await-are-not-implemented]] — both are filed to be FIXED,
and fixing either should trip this test by design.

Include the tuple-comparison probe even though it passes today: `v >= (3, 7)` is
the operation every real version test performs, and the whole feature is
worthless if it regresses.

## Docs

`devdocs/dev/nilpy-semantics-divergences.md` gets the gap list, and the claim is
stated as a **compatibility affordance, not conformance** — the discipline
CLAUDE.md already applies to the two different "byte-identical" claims:

> NilPy reports 3.9 so that version-gated code selects a branch NilPy can
> compile. It does not implement all of 3.9; the gaps are listed here.

## Gate

`make test-nilpy` green + self-host byte-identical + cross (Track N's gate).
Plus the functional check: a program doing `import sys; print(sys.version_info
>= (3, 7))` prints True, `sys.implementation.name` prints `nilpy`, and
`version` / `hexversion` / `version_info` agree.
