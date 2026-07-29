# Handoff prompt — NilPy bughunt, songformatter (2026-07-29)

Paste the block below into a fresh session.

---

You are Track **A+N+P** (compiler core / Nil-Python frontend / Pascal frontend),
bughunting on `master` in `/home/rene/frankonpiler`. Work directly on master,
commit in small units, push after each green gate. Gate = `tools/gate.sh quick`
(background it; it takes 8–15 min because Track T saturates this box — never
poll it every turn, wait for the completion notification).

## Where things stand

The driving case is **songformatter** (`~/songformatter`, a real CPython app
compiled with the NilPy frontend). Today it went from "dies rendering the first
document" to: full GUI, song loaded in the editor, redraw and key analysis
actually executing. Nine compiler/RTL fixes landed and are pushed (see
`git log --oneline` for `feat(nilpy)` / `fix(nilpy)` since `582f58e`).

Read first: **`devdocs/progress/backlog/bug-nilpy-slice-of-variant-local-returned-is-unusable.md`**
— it carries the whole bisect for the remaining wall, including two reverted
attempts. Also open: `bug-nilpy-zero-param-lambda-cannot-call-a-def`,
`bug-nilpy-callable-in-local-var-call-does-nothing`,
`bug-nilpy-tk-pxxcb-invalid-command-name` (root cause found and fixed — RE-VERIFY
whether the dialog is gone, the ticket may be closable),
`bug-nilpy-annotated-module-global-invisible-in-kwarg`.
Live ticket: `devdocs/progress/working/bug-nilpy-songformatter-first-render-walls.md`.

## The next thing to fix

`DetectorResult.evidence` in `key_analysis.py`'s `ViolationCountDetector` reads
back as garbage (`len()` answers 1751084129 — ASCII bytes as an integer) and the
join then segfaults. Established by bisect:

- The value is a CORRECT empty list when passed (`len()` right after the slice
  is 0) and garbage when read out of the field.
- `evidence=list(ev_local)` fixes it; `evidence=ev_local` does not. So a
  variant-held list lands in a class-typed field without anything taking a
  reference.
- **The mis-typing is UPSTREAM of the constructor.** Instrumenting the compiler
  showed that in the EMITTING pass 4 of the 8 `DetectorResult(...)` sites pass
  slot 4 as tyVariant and 4 as tyClass, and `violation_count` is a class-tagged
  one — its argument is already tyClass at the call while the run-time value is
  a variant. The typing pass and the emitting pass DISAGREE about it (8 vs 4).
- Ruled out: `PyWiden(tyVariant, tyClass)` correctly yields tyVariant;
  `PyMakeSlice` correctly returns tyVariant for a variant base (`pyvar_slice`);
  neither the ternary nor the slice lowering invents the class tag.

**Start here:** find where the local / the argument re-acquires a tyClass tag on
the SECOND parse — `PyNoteLocalType` widening, or the field's declared type
flowing back onto the expression. A two-pass type disagreement is the same shape
as the ABI mismatches already recorded in this frontend.

**Do NOT re-attempt** (both tried and reverted today, both no-ops for this bug):
adding `PyUnboxVariantToClass` to `PyClassCreate`'s keyword-argument path, and
routing `PyMakeDynCall` through `pyvar_callN`.

Incidental wart worth knowing: the synthesised dataclass `create` parameter is
class-TYPED but carries no record id (`ProcParamRecId` = 0) — the class identity
lives only in the field table (`UFldRec_`).

## Method that works

1. `rm -rf /tmp/sfx && cp -r ~/songformatter /tmp/sfx`, add `print` markers to
   the scratch copy (the app's unhandled-exception handler now prints
   `ClassName: Message`, so most walls name themselves without markers).
2. `cd /tmp/sfx && /home/rene/frankonpiler/compiler/pascal26 SongFormatter.py <OUT>`
   — **use a NEW output name every time**.
3. Run with `DISPLAY=:99` (an Xvfb is already up on :99; `import -window root
   <png>` screenshots it).

### Two traps that produce confident WRONG readings

- **A still-running instance makes the compiler's write a silent no-op**
  (ETXTBSY) — it still prints `ok: <path>`. `pkill -9 -f <path>` first, or build
  to a fresh name, and confirm with `ls -la` / `strings <bin> | grep <marker>`.
- **SIGTERM loses buffered stdout.** A `timeout`/`kill`ed run prints nothing, so
  "the callback never fired" is indistinguishable from "it fired and the output
  died". Give the test a clean exit path and read the output from that.

To locate a crash: the compiler emits a `.map` next to the binary —
`grep -v '^#' <bin>.map | sort | awk -v A=<0x-addr> '$1 <= A' | tail -1`
symbolises an address from `gdb -batch -ex run -ex bt`.

## Standing rules

- Land only green: `tools/gate.sh quick` before every push.
- Don't leave speculative changes in shared code — revert and file the finding
  instead (that is what happened twice today, and the tickets are better for it).
- File what you can't finish: `tools/progress.sh` + a ticket in
  `devdocs/progress/backlog/` with a minimal repro.
