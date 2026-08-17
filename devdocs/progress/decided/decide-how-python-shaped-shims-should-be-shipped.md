---
track: U
prio: 70
type: decide
blocked-by: []
summary: "A shim whose content is Python-level aliases (six: `text_type = str`) cannot be written in the mimic_<name>.pas slot, and the working alternative — a NilPy .py in a library root — silently defeats --no-shims. Three options, recommendation is to let the shim lookup also probe mimic_<name>.py."
---

> **REFRAMED (owner, 2026-08-17). The `--no-shims` argument was the wrong
> justification and is withdrawn.**
>
> *"`--no-shims` assumes the programmer knows what they are doing, and at that
> point we have no responsibility for the results. We do a best effort.
> Complicating our own code sounds wrong. The target is 'just works', not 'also
> works if the programmer chooses to opt out'."*
>
> Correct, and it kills the case as originally written: an opt-in audit flag does
> not earn complexity in the path every build takes. Do NOT harden the flag — no
> refusal machinery, no scanning for suspiciously-named library files, no
> guarantee that survives a determined programmer. It refuses the `mimic_`
> substitution and that is the whole of its claim; its help text should say that
> rather than imply "no compatibility code was used".
>
> **The decision nevertheless stands, on the owner's OWN earlier ruling**
> (`feature-nilpy-dotted-package-imports`, "Decided (Rene, 2026-07-26)"):
>
> > *"resolution is a MAPPING, and the unit keeps OUR name… **No file in the tree
> > carries the upstream name**, the tree says what each shim is."*
>
> A `lib/**/six.py` is a file in our tree carrying the upstream name. It
> contradicts that ruling directly, with no reference to any flag. `mimic_six.py`
> is the same rule applied to a shim that happens to be written in Python.
>
> So the change is **one extra probe** — `mimic_<name>.py` alongside
> `mimic_<name>.pas` — because the shim slot being Pascal-only is an accident of
> when it was written, not a design. `--no-shims` continuing to mean something is
> a SIDE EFFECT of the naming staying consistent, not the reason to do it.
>
> Default behaviour is unchanged: we keep mimicking whatever we cannot compile
> yet, and `tk` and `reportlab` keep working exactly as they do.

> **RAISED 45 -> 70 (coordinator, 2026-08-17): this is now the critical path for
> the NilPy corpus campaign.** Track N measured the 58-file ladder at HEAD and the
> walls are not frontend bugs — they are missing modules: **`six` alone gates 15
> of 58 files**, webencodings-as-a-unit 7, `xml_dom` 3, `warnings` 3. Three
> independent measurements now say the same thing: **Track N is not the
> bottleneck; the shims are.** Three N fixes landed today and the compile count
> did not move (4 on pinned, 4 at HEAD) — they moved walls deeper rather than
> past. So nobody can build the shims until this decision lands, and the campaign
> that the week's theme rests on is waiting on one answer.

# How should a Python-SHAPED shim be shipped?

- **Track U** (decision). Raised 2026-08-17 by frank3 (Track B) from
  [[feature-nilpy-six-and-warnings-shims]], which is parked in `unfinished/`
  behind it.
- Measured on `pinned` v344.

## The fork

`six` is a file of Python-level aliases — `text_type = str`,
`string_types = (str,)`, `integer_types = (int,)`. In CPython it is itself pure
Python. Two facts collide:

1. **The shim slot is Pascal-only.** `parser.inc:33210` probes
   `lib/pcl/mimic_<name>.pas`, then `lib/rtl/mimic_<name>.pas`, and nothing
   else. Expressing "the `str` type object, as a value" from Pascal is not
   something any existing shim does.
2. **A NilPy `.py` in a library root already works** — verified, output
   byte-identical to CPython:
   ```
   from six import text_type, PY3, binary_type, unichr, viewkeys
   print(text_type("x"), PY3, unichr(65), sorted(viewkeys({"a": 1})))
   pxx / CPython:  x True A ['a']
   ```
   …**but it silently defeats `--no-shims`.** That flag exists so "a build that
   succeeds provably used no compatibility shim" (`defs.inc:1571`), and it
   refuses only the `mimic_` substitution. A `lib/**/six.py` is a real library
   module by the resolver's own rules, so it satisfies `import six` under
   `--no-shims` and falsifies exactly the guarantee the flag sells.

## Options

**A. Write `mimic_six.pas` in Pascal.** Honours `--no-shims` with no compiler
change. But it has to express Python type objects as values from Pascal, which
no shim does today, for a file whose entire content is Python aliases. Highest
friction, and the result would be the least readable file in `lib/`.

**B. Ship `lib/pcl/six.py` as a NilPy library module.** Works today, zero
compiler change, and it is what the module actually is — CPython's `six` is a
pure-Python file too. Cost: `--no-shims` stops meaning what it says, silently,
for every shim shipped this way afterwards.

**C. (recommended) Let the shim lookup also probe `mimic_<name>.py`.** A small
Track N/A change beside the existing `.pas` probes. Then a Python-shaped shim is
written in Python, lives in the shim namespace, and `--no-shims` refuses it like
any other — the flag's guarantee is preserved *by construction* rather than by
everyone remembering the convention. It also removes the standing trap in B,
where any future `lib/**/<stdlib-name>.py` quietly becomes an unrefusable shim.

## Why this is a decision and not just work

B is the path of least resistance and is *wrong in a way that is invisible*:
nothing goes red, `--no-shims` keeps exiting 0, and it simply stops proving
what it claims. That is the "the property holds and nothing enforces it" shape
this repo has hit twice this week. It should be chosen deliberately or not at
all.

## What is NOT open

The `six` content itself — the name list, its scoping to what html5lib and
tinycss2 actually import, and the `viewkeys`-is-a-function trap — is settled in
the parent ticket and is unaffected by this. Only *where the file goes*.


## DECIDED (Rene, 2026-08-17)

> *"`--no-shims` is just 'unsupported'. Define it: we will not provide shims.
> Done. And not sneakily load other shims."*

Two rulings, and the second is what settles the open question.

**1. The flag's meaning is simply "unsupported".** It says we provide no shims for
this build. Nothing more is promised and nothing is hardened — no refusal
machinery, no scanning for suspiciously-named library files, no guarantee that
survives a determined programmer. Past the opt-out, the results are the
programmer's. Its help text should state what it actually checks.

**2. A shim must be RECOGNISABLE as a shim.** "Not sneakily load other shims" is
the operative half: a `lib/**/six.py` that satisfies `import six` while the build
reports no shims is not a broken guarantee, it is a **dishonest tree**. This is
the same rule as the 2026-07-26 ruling — *no file in the tree carries the upstream
name, the tree says what each shim is* — and it holds whether or not any flag
exists.

So: Python-shaped shims are named `mimic_<name>.py` and found by the same lookup
as `mimic_<name>.pas`. The shim slot being Pascal-only is an accident of when it
was written. `--no-shims` continuing to mean something is a consequence of the
tree being honest, never the justification.

**Re-filed as `feature-a-the-shim-slot-should-find-a-python-shaped-shim`** (A,
p70) — the lookup is `PyMimicShimExists` in `parser.inc`, shared ground, so it is
Track A work rather than N's.
