# C: two conflicting typedefs for one name are accepted silently, last wins

- **Type:** bug (Track C — C frontend, the typedef registration in
  `compiler/cparser.inc`)
- **prio:** 50
- **Status:** open

## Repro
```c
typedef long long T;
typedef long T;
int main(void){ return (int)sizeof(T); }
```
`gcc -m32`: `error: conflicting types for 'T'; have 'long int'`.
`pxx --target=i386`: compiles, no diagnostic, exit code 4 — the LAST typedef
won.

C11 6.7 permits a repeated typedef only when it names the *same* type. These
do not, so this must be an error.

## What it cost
It hid a genuine crtl inconsistency for the whole life of the file.
`<time.h>` had `typedef long long time_t` (with a comment promising 64-bit on
every target so Y2038 never appears) while `<sys/types.h>` had
`typedef __time_t time_t` with `__time_t == long`. Including `<time.h>`
auto-pulls `crtl/src/time.c` (`CPAutoPullCrtlImpl`), which reaches
`<sys/types.h>`, so the `long` definition arrived last and won — and no
diagnostic said the header's promise had been overridden.

The damage is not the width, it is that the width became a function of what
else the translation unit pulled in. Measured with the conflict restored, one
TU giving two answers for one type on i386:

```
sizeof(time_t)=4   sizeof(long)=4     <- the sizeof rows AGREE
static time_t g;   laid out at 8      <- and the global disagrees with them
```

On x86-64 the whole thing is invisible, because `long` and `long long` are the
same width there. The shape that passes where you test.

The crtl half is fixed (`<time.h>` now uses `__time_t`, one definition) and
`test/c_time_t_one_definition.c` guards it on i386/arm32/riscv32. The frontend
half — refusing the conflict — is this ticket.

## Care needed
Not a free error to add. `lib/crtl` deliberately redefines names the Pascal RTL
also spells, and `cparser.inc`'s cross-namespace binding has three rungs of
measured special-casing around exactly that. The check wanted here is narrow:
two `typedef`s in C for one name whose target types differ. Run the corpora
(zlib, lua, quickjs, the 220-case conformance suite, busybox) before landing —
a second conflicting pair somewhere would currently be compiling quietly.
