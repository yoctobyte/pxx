---
summary: "nilpy: printf-style % on a string yields garbage instead of formatting (silent wrong output)"
type: bug
track: N
prio: 60
---

# nilpy: `"%.2f" % value` produces garbage

- **Type:** bug (Nil-Python frontend, lowering) — **Track N**
- **Status:** done
- **Opened:** 2026-07-26 — probing songformatter under nilpy
  ([[feature-demo-songformatter-pxx-target]]).

## Severity: silent wrong output

Compiles clean and runs, printing a wrong value with no diagnostic. That is the
worst failure class we have — a program that looks like it works.

## Repro

```python
print("A", "%.2f" % 3.14159)      # CPython: A 3.14   -> pxx: A 0.0
print("B", "%d" % 42)             # CPython: B 42     -> pxx: B 39
print("C", "%s" % "str")          # CPython: C str    -> pxx: C 8568
print("D", "%.1f/%.1f" % (1.5, 2.5))  # CPython: D 1.5/2.5 -> pxx: D 5010409
```

The results look like the numeric `mod` operator being applied to a string /
pointer value rather than string interpolation, i.e. `%` is not being recognized
as string formatting when the left operand is a str.

## Lane note (2026-07-26)

The multiplicative-expression loop that would need the `str % args` case lives in
the SHARED `compiler/parser.inc` (~line 11736 for `tkMod`; the neighbouring
`PyExprMode` string/list/bytes-repeat cases for `tkStar` are the precedent at
~11706-11721), not in Track N's own `pyparser.inc`. So the hook itself is a Track A
edit even though the semantics are nilpy's — needs the sole-A check, or file the
parser.inc hook as a Track A ticket and keep the formatting helper in pyparser.inc.

## Fix shape

Recognize `str % value` and `str % tuple` in the nilpy lowering and route to a
formatting helper (the `{}`-style path presumably already has one; f-string specs
are the neighbouring gap, [[feature-nilpy-fstring-format-spec]]). Failing to
support a conversion must be a compile error, never a wrong value.

## Gate

`make test-nilpy` green with a `.npy` case covering `%s %d %f %.Nf` and the tuple
form, diffed against CPython, + `--tier quick` + self-host byte-identical.

## Still live 2026-07-28 (287b1b34d)

```
print("%s" % "s")        CPython: s       pxx: 5207332
print("%d" % 42)         CPython: 42      pxx: 36
print("%.2f" % 3.14159)  CPython: 3.14    pxx: 0.0
```

The integer case is the tell: 42 comes back as **36**, which is `42 mod 6` —
`"%d"` is being read as a numeric operand (its digit content) and `%` as the
arithmetic modulo, exactly as the original report guessed. So the fix is at the
`%` lowering, not in a formatting helper: when the LEFT operand is a string, the
operator is interpolation, and only then does the right side become the argument
tuple.

Sibling surface worth doing in the same pass: `"{} {}".format(a, b)` errors with
"takes exactly one argument here; several placeholders are not implemented yet".
That one is at least LOUD, unlike this.

## Attempted 2026-07-28 — NOT landed, and why

A full printf-style formatter was written and then **reverted**, because every
wiring of it left at least one shape silently wrong, and a half-right `%` is
the same failure class as the bug. What was learned is worth more than the
code, so it is recorded here.

### The runtime half works

`PyPercentFormat(fmt, args)` in pylib: conversions `s r d i u f F e g G x X o c`
and `%%`, with `-`/`0` flags, width and `.precision` (truncating for `%s`);
unsupported conversion or short argument list halts with the spec quoted. Args
are a single value or a TPyList (a tuple). Verified against CPython on literal
formats, tuple arguments, width/flag/precision combinations, `%x/%X/%o`,
report-style `"%-8s %3d %8.2f"` tables and `%%`. This part can be reused as is.

### The compiler half is where it fails

Three wirings, each correct for most shapes and wrong for one:

1. **Hand-built IR_ARG chain in ir.inc, `pypercent_s(AnsiString, Variant)`.**
   Works for literal arguments; delivers an EMPTY format string when the
   argument is a variant lvalue. The chain mixes an AnsiString and a Variant
   parameter, which is the shape
   [[project_irlowercallarg_hand_built_args_landmine]] warns about.
2. **Same, with both parameters `const Variant`** (mirroring pyfloormod_v, whose
   uniform pair the backends do lower correctly). Fixes the variant lvalue;
   a string LITERAL then arrives as its inline buffer address and the callee
   reads the literal plus trailing heap as its format.
3. **A real AN_CALL built in the parser** (like `PyMakeListRepeat`), so the
   ordinary argument lowering applies. Literal and tuple arguments are correct;
   a SUBSCRIPT argument (`d["k"]`, `l[0]`) still arrives as None, and the
   printed result was `True`.

A separate finding, needed by any of these: `ParseTerm` types a `%` node from
`TypeDivideResult`, so even with the call correct, `line = "%s" % x` binds a
NUMERIC local — the trial parse that types NilPy locals reads that field. The
node has to be typed tyAnsiString (or the call has to be built) at PARSE time,
not at IR lowering.

### What to do next

Find why a subscript argument boxes to None for this call while it boxes
correctly for `str(d["k"])` and `len(d["k"])` — that is one diff between two
lowering paths, and once it is understood, wiring (3) is a few lines. Do not
start from the runtime; that part is done.

### Known divergence to expect once it lands

`"%s" % [1, 2]` will print `1` where CPython prints `[1, 2]`: CPython reads a
TUPLE as the argument sequence and a LIST as one value, and a tuple lowers to a
TPyList here, so the sequence reading has to win (it is what `"%d,%d" % (a, b)`
needs). Tracked by [[bug-nilpy-str-of-tuple-is-empty]].

## Resolved 2026-07-29 (commits ee6a990f3, d468e887e)

Hooked in the shared parser's multiplicative loop on the LEFT operand being a str
(sole-A confirmed with the user, as this ticket's lane note asked), lowered to
pylib's `pypercent_format`, which translates each placeholder into the {}-spec
grammar the f-strings and `.format()` already use.

The tuple-vs-list question is the part worth remembering: Python takes a tuple as
a list of ARGUMENTS and a list as ONE value, but a NilPy tuple IS a TPyList, so
run-time type cannot decide it. The parser passes whether a tuple DISPLAY was
written (PyMakeTupleFrom's hidden `__py_tup_*` temp is the marker) and the
placeholder count covers a tuple arriving through a variable. Documented
divergence: `"%s %s" % [a, b]` walks the list where CPython raises.

Verified against CPython: width, precision, flags, %x/%X/%o, %%, tuples, a list
value, a tuple through a variable, and numeric `%` left untouched.

## Log
- 2026-07-29 — resolved, commit ee6a990f3.
