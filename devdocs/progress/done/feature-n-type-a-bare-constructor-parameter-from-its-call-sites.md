---
track: N
prio: 80
type: feature
blocked-by: []
summary: "A bare (unannotated) parameter of a constructor, method or module function takes the scalar type its call sites in the same file agree on, read token-only through caller locals and caller parameters; the field or parameter is typed instead of variant, so the demo's physics runs on SSE instead of the variant protocol. Grid.at loop 0.93 s -> 0.34 s. Three wrong-value bugs fixed on the way; ints are deliberately not claimed until every caller is visible."
status: done
---

# Type a bare parameter from its call sites

The lekkerzeilen demo has 334 constructor parameters and zero annotations,
which is how Python is written, so every field set from one was a variant and
every arithmetic op on every field ran the full dynamic protocol. Measured
2026-09-15 on `Grid.at`: annotating the parameters took it from 1337 B / 48
calls / 0 SSE to 280 B / 1 call / 3 SSE. The program does not get annotated
(programs do not contort for the frontend); the compiler reads what the call
sites already say.

**Mechanism.** `PyParamTypeFromSites(defTok, pname, mode, cls)` in
`pyparser.inc`, token-only like every pre-pass scanner, memoised per
(def token, name) so the three header passes agree. Mode 0 = constructor
(`Cls(` sites), 1 = method (`.name(` sites; `Cls.name(` skipped), 2 = module
function (`name(`). The default is a site of its own and anchors; every visible
site must agree on ONE scalar (float, int, bool, str) or the answer is unknown.
An argument that is the caller's bare parameter recurses into the caller's
sites; one that is the caller's LOCAL is typed by `PyLocalScalarType`, which
needs every binding to agree and accepts the accumulator idiom (`x = x + dt`,
`x += dt`) only when it keeps the type. A parameter the body REBINDS is checked
the same way. Only the def's OWN FILE is scanned (`PasSrcRangeStart` bounds):
imported modules and the builtin Pascal units share the token stream, and an
unbounded scan met `parts.at(k)` in pylib.pas and vetoed `Grid.at`.

**Two wrong values found by the fixture's controls, both pre-existing:**
`def probe(q): return q * 3` answered 4 for probe(1.5), because the return
scan joined the unknown parameter with the literal and typed the return
Int64 (now: an untyped bare parameter read in a return expression makes it a
variant, `PyRetExprHasUntypedParam`). And `response.read()` with `response`
bound by `with ... as` was typed Int64 from a module-level `read` in another
module, because the expression typer's call arm fell back to a global proc
lookup for a dotted non-unit root (now: no fallback for a dotted root).
A third, bisected by the lekkerzeilen seat from the demo's `keel()`: `return
self.section(t)[0][1]` typed Int64 from the INDEX literals, because the call
arm leaves the walk on the `[` and the indices were joined as operands (1.75
came out 1; `r = self.section(t); return r[0][1]` was correct). Now a `[`
after `)` or `]` is a subscript: the element is a variant, the group skipped.

**Behaviour the typing changed, kept CPython-shaped.** `def f(vm): del
vm[1:2]` with every site passing a str: `vm` is a str now, and a str's `del`
was a compile error where the variant raised CPython's TypeError at run
time. `pystr_del_at`/`pystr_del_slice` raise it at run time instead
(test_nilpy_del_of_a_slice_on_a_variant_receiver's last row, which caught
it on the tier). The tier also caught a bool default typed Int64: Boolean
is a machine int to PyIsMachineIntTk, so `PyIsSiteIntTk` excludes it.

**Ints are NOT claimed, and that is the second finding of the evening.** The
lekkerzeilen seat ran its value-parity test against the real modules: `text.
measure(line, scale=2)` typed int from its ONE own-file site while all four
real callers sit in ui.py/app.py, invisible to an own-file scan, and 80 of the
357 typed parameters rested on a single int site. An int claim is the one a
caller the scan cannot see defeats silently (a variant 1.25 truncates to 1;
a static 1.25 is a compile error for a program CPython runs). A float claim
is safe both ways (an int widens exactly, a str raises), so floats and strs
are claimed and an int OR BOOL site or default VETOES (a float claim over an
int site would print 6.0 for 6; a bool field typed from `v=True` turned a
later `self.icon.visible = 11` into True where CPython keeps 11 --
test_nilpy_chained_assign_nested_attr, on the tier). The demo's hot path is float. Ints come
back with feature-n-lex-the-import-closure-before-parsing-so-call-site-typing-sees-every-caller.

**A float parameter reaches pyeval's host-method dispatch**, which took only
Int64-register shapes (plus a lone fpush/fpop pair) and Halted with
"unsupported param shape" on `at(self, x, z, outside=77.5)` once `outside`
was a Double (test_nilpy_dynamic_call_takes_defaults_from_its_own_class, on
the tier). pyeval.pas now has the MIXED family: m pointer-class args and k
doubles, one thunk per (m, k, result kind), relying on SysV assigning the two
register classes independently of interleaving; a Double result with n > 0
is now read from xmm0 too (it read rax before).

**Known residual, owner: this seat.** A variant holding a double coerced into
an int-typed slot TRUNCATES silently (`pyvar_to_int`), so an int claim is the
one answer a foreign-module caller can defeat without a diagnostic. Float,
str and bool claims fail loudly. The local typer refuses an int base that
takes a float step for exactly this reason.

Fixture: `test/test_nilpy_a_bare_parameter_is_typed_from_its_call_sites.npy`
(value row + a `PXXDBG=n.psites` census row; the census is the only
instrument that can see the typing).

## Log

- 2026-09-15 frankuser (Fable): built, measured on bench2 (0.93 s -> 0.34 s, output 661050096 both) and on the demo compile; commit 7bf3860e0.
