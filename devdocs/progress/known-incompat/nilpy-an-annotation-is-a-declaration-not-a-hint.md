---
track: N
prio: 0
type: known-incompat
blocked-by: []
summary: "MEASURED 2026-09-09: NilPy treats a variable annotation as a DECLARATION where CPython treats it as a hint, uniformly for fields and locals. `self.a: float = t` with t=2 prints 2.0 against CPython's 2; `a: float = t` in a plain def does the same, which is what shows it is the annotation rule and not a field rule. CHOSEN, not tolerated: the annotation is how a NilPy field gets a static type at all -- the compiler's own diagnostic says `annotate it (self.a: int = ...)` -- so an annotation that did not determine storage would make that advice meaningless. ONE ROW DESERVES A SECOND LOOK and is named below rather than buried: `self.a: int = t` with t=2.7 stores 2, silently."
status: known-incompat
owner: —
---

# An annotation is a declaration here, a hint in CPython

## Measured, one program per row

| program | pxx | CPython |
| --- | --- | --- |
| `self.a: float = t`, `t=2` | `2.0` | `2` |
| `a: float = t` in a plain def, `t=2` | `2.0` | `2` |
| `self.a: int = t`, `t=2.7` | `2` | `2.7` |
| `self.a: int = t`, `t="s"` | `TypeError` at run time | `s` |

## Why this is chosen and not a defect

An annotation is the ONLY way a NilPy field or local acquires a static type,
and the compiler says so in its own voice — `cannot infer the type of field
self.a - annotate it (self.a: int = ...)` is the diagnostic that half this
lane's tickets are about. If an annotation did not determine storage, that
advice would be advice to write something inert. The rule is also **uniform**:
locals behave exactly as fields do, which is evidence of a design rather than
of a field-inference accident.

Both answers are correct about their own implementation. CPython's annotations
are metadata by specification; ours are a declaration in a dialect that
compiles to machine code, and PXX's own architecture note — *"compatible with
FPC means the VALUE, not the intermediate's type"* — is the same shape of call
one layer down.

## The residual question, and who owns it

**`self.a: int = t` with `t = 2.7` stores 2 with no diagnostic.** That is a
wrong value rather than a wider one, it is silent, and "silent" is what
separates it from the other three rows. It follows from the same chosen rule,
so it is recorded here rather than filed as a bug — but the reasoning that
makes the float row obviously fine does not obviously cover it.

**What would settle it:** real source that annotates `int` and stores a float,
correct under CPython and wrong under pxx. Absent that, this stays as it is;
CLAUDE.md's own test — *prefer the answer that leaves the mistake visible* —
arguably points at a diagnostic here rather than at CPython's answer. A
narrowing conversion warning would satisfy both readings and change no value.

Found while probing every rung of `PyInferFieldDecl` for
`refactor-n-the-field-type-pre-pass-asks-one-question-in-six-places`; not
looked for.

---

**A NARROWING WARNING IS COMPATIBLE WITH THE CHOSEN SEMANTICS** (frankuser,
2026-09-09, and it sharpens the residual above rather than reopening it).
"Chosen" covers the RULE — an annotation declares storage — and it does not
cover the SILENCE. `self.a: int = t` with `t = 2.7` loses a value with no
diagnostic, and a warning at the narrowing store would satisfy both readings
while changing no value and no type. Same shape as the closed-world case one
lane over: a WARNING is compatible with the behaviour we want, a REFUSAL is
not. Still not worth a fix without real source that wants it — a probe cannot
settle whether anyone writes this — but if someone touches this area, the
warning is the cheap half.
