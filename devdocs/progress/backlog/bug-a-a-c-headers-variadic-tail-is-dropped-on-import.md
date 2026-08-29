---
prio: 45
track: A
type: bug
blocked-by: []
summary: "A C prototype's `...` is discarded when the header is imported into Pascal, so every variadic C function is callable only with its FIXED prefix. printf imports as printf(Pointer). C mode itself calls varargs correctly, so the machinery exists and only the import discards it."
---

# A C header's variadic tail is dropped on import

Found 2026-08-29 by frankR while migrating `lib/pcl` off the curated
`gtk3_c.h` ([[feature-b-migrate-pcl-off-the-curated-gtk3-header]]). It is the
one thing that blocks that migration completely.

## Repro

```pascal
program v;
uses vartest_c;        { a header whose whole body is #include <stdio.h> }
begin
  printf(PChar('a=%d b=%d'#10), 7, 9);
end.
```

```
error: no overload of printf matches these arguments
  argument types: (AnsiString, Integer, Integer)
  candidates:
    printf(Pointer)
```

`printf` imports with **one** parameter. The `...` is gone, and with it every
variadic C function in every header: `printf`, `g_signal_emit_by_name`,
`gtk_message_dialog_new`, `g_object_set`, `g_object_get`, `execl`, `open` — the
whole family is reachable only through its fixed prefix.

## The capability is NOT missing — only the import discards it

This is the part that makes the ticket cheap, and it was measured rather than
assumed:

```c
#include <stdio.h>
int main(void){ printf("a=%d b=%d\n", 7, 9); return 0; }
```

compiled by pxx in **C mode** prints `a=7 b=9`. So the call lowering already
marshals a variadic call correctly (including zeroing `al` for the x86-64 SysV
requirement). What is missing is the plumbing that would let a *Pascal* caller
reach it:

- `compiler/cparser.inc:12692` — in the fn-pointer typedef path the `...` marker
  is consumed with a bare `Next` and nothing records it. The prototype path is
  the same shape.
- `RegisterProc` / `Procs[]` have **no varargs flag at all**. There is nowhere to
  put the fact even if the parse kept it.
- `compiler/pasparser_call.inc:963` — Pascal's own `varargs` directive is parsed
  as an **inert** routine directive, in a list with `deprecated`, `platform` and
  `library`. It is accepted and thrown away, so a hand-written
  `external ...; varargs;` declaration cannot express it either.

So the fix is a flag through those three places plus the arity check at the call
site, not new codegen.

## Why it matters beyond convenience

`gtk_message_dialog_new(parent, flags, type, buttons, "%s", text)` is the
idiomatic GTK spelling and cannot be written. The migration works around it with
`gtk_message_dialog_new(..., NULL)` + `g_markup_escape_text` +
`gtk_message_dialog_set_markup` — three calls, and the escape is load-bearing
because `set_markup` interprets Pango markup where `"%s"` did not. That is a
correct workaround and it is also exactly the kind of reshaping
`devdocs/dev/normalise-dont-special-case.md` and the platonic-code rule tell
Track B not to do. One site in `test/gui/test_pcl_input.pas`
(`g_signal_emit_by_name(handle, signal, event, @handled)`) has **no** clean
non-variadic route at all and is left failing rather than rerouted, per the
platonic-code rule.

## Note on the fixed-prefix call, which DOES work

Calling a variadic callee with only its declared fixed parameters is safe today
and verified against real GTK3: `gtk_message_dialog_new(nil, 1, 0, 1, nil)` and
`gtk_file_chooser_dialog_new(title, nil, action, nil)` both return live widgets
and the callee's `va_start` finds an empty list. So the import is not producing
a *wrong* call — it is producing a *narrower* one. That is why this is a missing
capability rather than a miscompile, and why it is prio 45 rather than higher.
