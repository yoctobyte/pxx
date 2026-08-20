---
slug: feature-n-a-cpyext-extension-module-is-bare-importable-not-a-pascal-unit
track: A+N
prio: 70
status: backlog
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
