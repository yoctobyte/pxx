---
slug: feature-n-a-cpyext-extension-module-is-bare-importable-not-a-pascal-unit
track: A+N
prio: 70
status: done
owner: frank3
---

# A cpyext extension module is a Python module, not a Pascal unit — make it bare-importable via `PyInit_<name>`

The implementation half of
[[decide-nilpy-import-rule-vs-a-cpyext-extension-module]], **decided by the owner
2026-08-20**. Read that ticket's `## DECIDED` section before starting — it settles the
shape, and two of its four parts correct framings that look reasonable if you re-derive
them from scratch.

## The decision, in one line

The import rule ("a bare NilPy import resolves to Python only; reach a Pascal unit by
naming its extension") is **affirmed unchanged**. An extension module simply is not its
subject: it is a Python module whose body happens to be Pascal + C, so bare
`import <name>` is correct for it and the rule never applies.

## What to build

At the refusal site — `compiler/parser.inc:34223`, which fires *after* the resolver has
already found and read the unit and holds `pasRefusedPath` — an extension module must
resolve instead of erroring.

**Criterion: `PyInit_<name>`.** Preferred shape is **(b)**: the unit DECLARES itself an
extension module and `PyInit_<name>` VERIFIES the claim, so a missing or misnamed
`PyInit_` is a *diagnostic* rather than a silent mis-resolution. Fallback **(a)** — grep
the unit's `uses`-clause `.c` files for `PyInit_<lo>` at resolve time — is acceptable if
(b) needs more machinery than it earns. **State which you chose and why, in this ticket.**

## Two things NOT to do

- **Do not key on the `_ext` name suffix.** Measured on CPython 3.12.3: of **147** real
  extension modules (48 stdlib `lib-dynload` + 61 statically builtin + 99 third-party
  `.so`), **zero** end in `_ext`; 70 begin with a leading underscore (`_socket`, `_json`,
  `_ssl`, `_imaging`, `_psutil_linux`). The six test units' `_ext` names are test-local
  naming invented by the cpyext suite's author. A name-suffix predicate would be a
  coincidence-proxy built on a convention that does not exist —
  see [[project_a_proxy_standing_in_for_the_real_question]].
- **Do not rewrite the six tests to the quoted spelling.** That was rejected: it would
  leave the cpyext suite not testing its own subject.

## Verify

The six jobs go green with their bare imports **unchanged**:
`test_cpyext_hello`, `test_cpyext_args_errors`, `test_cpyext_containers`,
`test_cpyext_markupsafe`, `test_cpyext_errformat`, `test_cpyext_cython`.
Ordinary Pascal units must still be refused a bare import — keep a negative test, or the
carve-out silently widens into the rule it was carved out of.

Gate: this lane's normal per-fix loop.

## COORDINATION — read before claiming

The site is in the **shared `compiler/parser.inc`**, so this carries **Track A
file-ownership** despite being N-flavoured work. It must not be worked while another
agent holds that file. As of filing, frank3 holds `parser.inc` for the `ParseFactorCore`
carve (`feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets`), which is
a multi-session job. Claim through the coordinator.

## 2026-08-20 — the site MOVED, and the file is now free

Split 3 of the carve deleted 764 lines from `parser.inc` at ~9515 (`3c8ec4c7d`), so
everything below shifted **-764**: the refusal site is **~33459**, not 34223.

**Do not navigate by line number — the landmark is unchanged:** the `THE COLLISION, NAMED.`
comment block immediately above
`if (Length(UnitContent) = 0) and isNilPy and (pasRefusedPath <> '')`.

`parser.inc` is no longer held by the carve. This ticket and
[[refactor-a-one-resolved-file-identity-for-a-translation-unit]] both live in the same
region of that file (this at ~33459, `ParseUsesUnit`'s dedupe at ~34590), so they
**serialise by construction** — one agent takes both in sequence rather than two agents
colliding over unrelated tickets. Assigned together 2026-08-20.

---

## RESOLVED 2026-08-20 (frank3) — shape (b), with the verifier substituted

### What landed

`compiler/parser.inc`, at the point the resolver throws away a Pascal unit it has
already found and read (`pasRefusedPath := ''`, ~33422 — *not* the error site at
~33463, which only reports what that line decided):

```pascal
  if (Length(UnitContent) > 0) and (not pasLookupOK) and PathIsPascalSource(path) and
     not ((pyImportLang = 'py') and PyUnitDeclaresExtensionModule(UnitContent)) then
```

`PyUnitDeclaresExtensionModule` is two textual tests over the unit source the
resolver is already holding — no file loading, no path resolution, no C read:

1. a line consisting of exactly `{$PYEXTENSION}` — the DECLARATION;
2. `pyruntime.c` somewhere in the source (i.e. its `uses` clause binds the cpyext
   runtime) — the CHECK.

The six units carry the directive above their `interface`. `{$PYEXTENSION}` needs
no lexer change: `ProcessPasDirective` already ends with *"Unsupported compatibility
directives remain accepted comments."*

### Shape (b), as preferred — and it cost almost nothing

Chosen because the machinery (b) was suspected to need did not materialise: the
declaration is a directive the lexer already tolerates, and both probes are
substring tests on a string already in hand. (a) — grepping the unit's `uses`-clause
`.c` files — would have needed uses-clause extraction, path resolution relative to
the unit, and per-file loads, i.e. strictly *more* machinery for the inferior
answer. So the decision's tie-break never had to be exercised.

### The verifier is NOT `PyInit_<name>` — that criterion is falsified by measurement

Measured on the six units this ticket requires green:

| unit | `PyInit_` present in its `uses`-clause C | is it `PyInit_<name>`? |
| --- | --- | --- |
| `hello_ext` | `PyInit_hello_ext` | yes |
| `argerr_ext` | `PyInit_argerr_ext` | yes |
| `container_ext` | `PyInit_container_ext` | yes |
| `cyadd_ext` | `PyInit_cyadd` (`vendor/cyadd_cython.c`) | no — the **vendored** module's name |
| `markupsafe_ext` | `PyInit__speedups` (`vendor/_speedups.c`) | no — same |
| `fmt_ext` | none anywhere | no — it is a C-API **consumer**, not a module |

Counting rule: `grep -o 'PyInit_[A-Za-z0-9_]*'` over `test/nilpy_units/**` and
`lib/cpyext/src/pyruntime.c` (which defines none), attributed to a unit by its
`uses` clause.

`PyInit_<name>` therefore verifies **3 of 6**. The two vendored cases are the
interesting ones — a real extension's init symbol is the *upstream module's* name
and the unit's `_host.c` shim adapts it (`markupsafe_ext_host.c` literally declares
`extern PyObject *PyInit__speedups(void);`) — so the mismatch is the normal case for
a genuinely vendored extension, not a test-corpus quirk. `fmt_ext` has no module at
all. Making the criterion hold would have meant adding a stub `PyInit_fmt_ext`: that
is fabricating evidence to satisfy a predicate, the same failure the `_ext` suffix
was rejected for.

Substituted check — **the unit binds the cpyext runtime** — is the nearest recorded
fact that holds for all six and for no ordinary Pascal unit (exactly those six of
the 20 `.pas` files in `test/nilpy_units/` name `pyruntime.c`). It keeps the
decision's structure intact: declaration = the fact, second test = the guard against
a declaration pasted onto an ordinary unit. **This deviates from the decided
criterion and is flagged for the owner to overrule.**

### The comment-scan caveat, found the hard way

First cut matched `{$pyextension` anywhere in the source. The negative-test unit's
own header comment says the words "carries no extension-module directive" — an
earlier wording spelled the directive out, and that unit was admitted as an
extension module. Tightened to *a line that is exactly the directive*. What remains
matchable is a commented-out directive alone on its line, which is a unit opting in
in its own source either way. A pre-lex scan cannot do better without a lexer, and
a lexer here would mean parsing the unit to decide whether to parse the unit.

### Verify — measured, at the SHA below

All six green with their bare imports **unchanged**, output matching each job's
Makefile expectation:
`test_cpyext_hello` 42 · `test_cpyext_args_errors` · `test_cpyext_containers` ·
`test_cpyext_markupsafe` · `test_cpyext_errformat` · `test_cpyext_cython`.

Negative side, both:
- pre-existing `test_nilpy_bare_import_is_python` (an RTL unit, `classes`) still refused;
- **new** `test_nilpy_pyextension_declaration_required` — `test/nilpy_units/undeclared_ext.pas`
  binds the same cpyext runtime and omits the directive, and is still refused by name.
  Wired into the Makefile beside the existing negative. This is the anti-widening
  test: it pins the carve-out to the declaration, not to the `-Fu` root and not to
  what the unit links.

Gate: `make compiler/pascal26` fixedpoint converged in 1 round; `tools/gate.sh quick`.

### Follow-up left for another lane

`docs/language/name-resolution.md:47` and `docs/targets/nil-python.md:260` quote the
refusal message and state the rule without the extension-module carve-out. Prose in
`docs/**` is **Track D**; not edited here.

## Log
- 2026-08-20 — resolved, commit PENDING-COMMIT.
