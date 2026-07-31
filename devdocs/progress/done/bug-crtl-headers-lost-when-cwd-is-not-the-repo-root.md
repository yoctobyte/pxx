---
summary: "C: pxx's own crtl headers are found only from the repo root — elsewhere <stdarg.h>/<math.h> silently come from /usr/include"
type: bug
track: C
prio: 60
---

# The crtl header root resolves against CWD, so building outside the repo root silently uses glibc's headers

- **Type:** bug (C frontend / preprocessor — **Track C**, `compiler/cpreproc.inc`)
- **Opened:** 2026-07-31 by Track B, walking songformatter's GUI modules for
  [[feature-nilpy-tkinter-facade-widening]]. Filed, not fixed: the fix is in
  shared compiler internals.

## Symptom

`~/songformatter/render_backend.py` (and `convertrawtext.py`, and
`SongFormatter.py`) fail to compile — but ONLY when the compiler is invoked from
their own directory, which is the only way a real user would ever invoke it:

```
$ cd ~/songformatter
$ pxx render_backend.py out
pascal26:9253: warning: undeclared identifier 'aq' used as value (treated as 0)
pascal26:9255: warning: undeclared identifier 'ap' used as value (treated as 0)
pascal26:9262: error: IR_UNSUPPORTED: frontend could not lower AST node (kind 1)
  near:   return len   >>> static ssize_t dstr_append_data
```

The same file, same flags, from `~/frank2`: **ok**. The `.py` is irrelevant — the
failing code is `lib/vendor/pdfgen/pdfgen.c`, pulled in as a UNIT by
`lib/pcl/mimic_reportlab_pdfgen.pas` (`uses '../vendor/pdfgen/pdfgen.c'`), which
any `import reportlab` reaches.

`ap`/`aq` are `va_list`. They are undeclared because `<stdarg.h>` came from
`/usr/include`, where `va_list` is spelled with gcc builtins pxx does not have.

## Root cause

`AddDefaultCIncludeDirs` (`compiler/cpreproc.inc:1883`) registers two roots:

```pascal
if ExeDir <> '' then
begin
  ConcatThree(ExeDir, '../lib/crtl/include/', '', d);   { assumes ExeDir = <root>/compiler/ }
  AddCIncludeDir(d);
end;
AddCIncludeDir('lib/crtl/include/');                    { CWD-relative }
```

The comment says the ExeDir anchor "resolves regardless of CWD". It does — for a
compiler built in place at `<root>/compiler/`. It does **not** for the binary
everyone actually runs: the stable/pinned one lives at
`<root>/stable_linux_amd64/default/pinned`, so `ExeDir + '../lib/crtl/include/'`
is `<root>/stable_linux_amd64/lib/crtl/include/`, which does not exist. That
leaves only the CWD-relative root — so pxx finds its own C headers **iff you run
it from the repo root**, and falls through to `/usr/include` otherwise.

Confirmed by construction: copy the same stable binary into a layout that DOES
have `../lib` next to it and the compile gets 5 lines into pxx's own `stdarg.h`;
without it, the same invocation gets 708 lines into glibc's.

Note `builtin/` does not have this problem — `parser.inc:26881` looks for
`ExeDir + 'builtin/'` and the stable layout ships exactly that. The Pascal unit
roots (`../lib/rtl`, `../lib/pcl`) miss for the same reason as crtl, but harmlessly:
every caller passes `-Fulib/rtl -Fulib/pcl` explicitly and a missing unit is a
hard error. The C include root is the dangerous one because missing it is
**silent** — `/usr/include` answers instead.

## Why this is a bug and not a packaging nit

The failure mode is the one this repo treats as worst: a wrong VALUE, far from
the cause. Alongside the `va_list` break the same compile reports

```
warning: undeclared identifier 'M_SQRT2' used as value (treated as 0)
```

— a math constant silently becoming `0` in a PDF geometry routine. Nothing
crashes; the output is just wrong. Any C corpus built from its own source
directory is exposed.

## Shape of a fix (Track C's call)

Three candidates, not mutually exclusive:

1. **Anchor for the shipped layout too** — also register
   `ExeDir + '../../lib/crtl/include/'`, so `<root>/stable_linux_amd64/<x>/pxx`
   resolves. Cheapest; still guesses at a directory depth.
2. **Ship the headers next to the binary**, as `builtin/` already is, and look
   for `ExeDir + 'crtl/include/'` first. Makes the stable binary
   self-contained, which is what a distributed compiler should be.
3. **Diagnose the fallback.** Whatever the search does, taking `<stdarg.h>` from
   `/usr/include` should WARN. The wrong-ABI risk is called out in that
   procedure's own comment; a program that hits it deserves to be told.

(3) is worth doing regardless of which of (1)/(2) lands.

## Reproduce

```sh
cd /tmp && pxx -Fu<root>/lib/pcl -Fu<root>/lib/rtl -Fu<root>/lib/rtl/platform/posix \
    <any .npy that does `from reportlab.pdfgen import canvas`> out    # fails
cd <root> && pxx ... same ...                                        # ok
cd /tmp && pxx -I<root>/lib/crtl/include -I<root>/lib/crtl/include/sys \
              -I<root>/lib/crtl/src ... same ...                     # ok
```

## Gate

C tests green + self-host byte-identical; plus a regression that compiles a
`.c`-as-unit from a CWD that is NOT the repo root and asserts pxx's own
`<stdarg.h>` was the one used.

## Log
- 2026-07-31 — resolved, commit 4215e1675.
