# Handoff — NilPy bug hunt, with the new debugging toolkit

Paste the block below as the opening prompt of a fresh session.

---

You are Track N (Nil-Python frontend), with Track A (compiler core) when a fix
needs shared ground — confirm with the user that no other agent holds A before
editing `ir*.inc` / `symtab.inc` / `defs.inc` / the backends. Work directly on
master in `/home/rene/frankonpiler`. Commit in small units; push after each
green gate.

## Read this first, before touching anything

`devdocs/dev/debugging-playbook.md` — which debugging tool, in which order. A
full toolkit landed 2026-07-29 and **this session is partly a test of whether it
gets used**. The failure mode is not that the tools are missing; it is reaching
for `print` and a rebuild out of habit.

The one-line rule it is built on: **the expensive bugs here do not crash, they
produce a plausible wrong value far from the cause.** A crash has a location and
is the cheap case.

Concretely, before you theorise about any wrong answer:

```sh
tools/pydiff.py run    prog.py      # NilPy vs CPython — stdout + exit code
tools/pydiff.py bisect prog.py      # names the first diverging statement
tools/pydiff.py probe               # standing corpus (7/8 pass; the 8th is a real open bug)
```

and before you theorise about what the compiler did:

```sh
PXXDBG=n.locals    compiler/pascal26 prog.py out   # inferred local types
PXXDBG=n.ctorargs  compiler/pascal26 prog.py out   # construction arg types
PXXDBG=a.ir:<proc> compiler/pascal26 prog.py out   # IR of ONE routine
PXXDBG=help                                        # the rest
```

`PXXDBG` exists *because* patching a probe into the compiler and self-compiling
(~90s) was slower than reasoning — so reasoning won, and it put a **wrong root
cause into a ticket** that survived two sessions and two reverted fixes. Do not
theorise about an inferred type. Print it.

For memory corruption: `-dPXX_HEAP_DEBUG` (freed bytes become `$DD` instead of a
recycled neighbour's plausible value), then `-dPXX_OBJTRACE` + `grep <addr>`.
Tell that selects it: the bug needs heap churn in between, or `list(x)` fixes it
and `x` does not — that is ownership, not typing.

For stepping: `-g -O2` (both work; `-O2` is where ownership bugs live), then
`gdb ./out`, `source tools/pxx-gdb.py`, and `pxxrc <obj>` for the refcount —
which lives at `[inst-16]` and is otherwise invisible.

## The work

`tools/progress.sh next` for the ranked queue. But look at the top of Track N
before pulling one ticket:

```
[p 75] bug-nilpy-def-value-in-a-variable-is-not-callable
[p 70] bug-nilpy-callable-in-local-var-call-does-nothing
[p 70] bug-nilpy-zero-param-lambda-cannot-call-a-def
[p 70] feature-nilpy-function-values
[p 65] bug-nilpy-bound-method-coerced-to-string
[p 65] feature-nilpy-bound-method-value
```

**That is one family, not six tickets: how NilPy represents a callable value.**
`PyMakeFuncValue` boxes a def as `pybound_new(@f, nil)` — a VT_BOUNDMETHOD (tag
8) variant whose payload is a `{Code, Recv}` pair OBJECT, not a code address.
`PyMakeDynCall` then takes `pyvar_callee_addr(v)` = the raw payload and jumps to
it, i.e. to the pair. Meanwhile a lambda yields `tyPointer`, so `ParsePostfix`
never routes it to the dynamic-call path at all and the call is silently
dropped.

So there are two different broken representations and three call paths that
disagree about them. **Start by mapping the representation, not by fixing the
top ticket** — a single coherent "what IS a callable value" answer plausibly
closes most of the list, and patching them one at a time will not converge.
`feature-nilpy-function-values` is the design ticket; read it first.

Minimal repro, already in the pydiff corpus as `def-value-in-a-name`:

```python
def f(ch: str) -> str: return "hi " + ch
def g(cb) -> str: return cb("x")
print(g(f))   # ok
x = f
print(g(x))   # SIGSEGV
```

Cheap partial fix identified but NOT applied: in `pyvar_callee_addr`, tag 8 with
`Recv = nil` should return `Code`. The complete fix follows the existing
`PyWrapClosureDynCall` shape (guard on `pycallback_is`, prepend the receiver
when non-nil). Decide which after reading the design ticket — do not just apply
the cheap one and call the family closed.

## Gate discipline

- **`tools/gate.sh quick` per fix, then push** — including for frontend and
  shared-IR changes. This bullet used to say "`full` when the change touches a
  frontend or shared IR"; that is superseded. Breadth is Track T's job, and it
  runs against your exact SHA, so widening the local gate costs ~10 minutes to
  buy coverage you were getting free — and delays the push, which delays T
  seeing the commit at all.
  Two facts behind the old advice are still true and still worth knowing:
  `--tier quick` covers **zero C/Rust/Zig jobs**, and `test-nilpy` is **no
  longer inside `quick`** (it was 625 of the gate's 649 seconds and was removed).
  The conclusion changed, not the facts: that uncovered surface is what T's
  limited/full tiers exist to sweep. Run a full gate yourself only when T is
  **proven** down — `tools/twatch.py --status` exit 1 (`git fetch` first; it
  reads the local `tstate/`).
- Background the gate and wait for the notification. **Do not edit compiler
  sources while a gate runs** — it invalidates the run. That happened twice in
  the session that built this toolkit; both had to be re-gated.
- Every debug switch must stay OFF by default with the emitted output
  byte-identical. Verify it, do not assume: compile a NilPy and a Pascal program
  with the old and new compiler and `cmp`.

## Traps that produced confident wrong readings

- **Stale binary.** A still-running instance makes the compiler's write a silent
  no-op (ETXTBSY) while still printing `ok:`. `pkill -9` first or use a fresh
  output name.
- **Lost stdout.** SIGTERM discards buffered output, so "the marker never fired"
  and "it fired and the output died" are indistinguishable. Give tests a clean
  exit.
- **Editing by slicing on a bare function signature** matches the INTERFACE
  declaration in a unit and eats the section. Anchor edits on body text and
  assert the match count is 1.
- **Never write `until ! pgrep -f "make X"; do sleep; done`.** `pgrep -f`
  matches the WAITER'S OWN command line, so it waits for itself and spins
  forever. The session that wrote this left 57 such orphans on the box, oldest
  20.6 hours, across several sessions. The loop is also unnecessary: a
  backgrounded command notifies on completion. If you must match a process, use
  `pgrep -f 'ma[k]e X'` so the pattern cannot match itself — that trick is also
  how you verify the cleanup worked, because a naive count counts itself.

## State

Songformatter (`~/songformatter`, a real CPython app) is the driving case. It
renders, and key analysis now matches CPython exactly. The next wall on the full
`analyze_key` path is the callable family above.

Reproduce headlessly — do NOT drive the GUI:
`rm -rf /tmp/sfx && cp -r ~/songformatter /tmp/sfx`, then a four-line driver
importing the module under test. ~1s per round, against `python3` as the oracle.
Xvfb is only needed for tk walls.

Also open, unrelated to the family:
`bug-compiler-selfdebug-lines-index-expanded-source` (Track A, prio 45 — the C
preprocessed-text fix one layer up; most of that fix is reusable) and
`decide-runtime-primitive-layering`'s remaining items (the raw-syscall invariant
and cross-surface conformance tests).
