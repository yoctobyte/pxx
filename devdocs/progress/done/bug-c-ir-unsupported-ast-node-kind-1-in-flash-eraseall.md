---
slug: bug-c-ir-unsupported-ast-node-kind-1-in-flash-eraseall
title: "C frontend cannot lower AST node kind 1 in miscutils/flash_eraseall.c"
track: C
prio: 55
type: bug
status: done
created: 2026-09-02
found-by: frankD
summary: "ROOT-CAUSED, AND IT IS NOT A COMPILER LOWERING GAP -- it is the FOURTEENTH crtl gap, so all fourteen refusals at 394 applets are crtl surface and NONE is a frontend lowering defect. `loff_t` is undeclared in crtl (only `__kernel_loff_t` exists, linux/types.h:39), so `loff_t offset = erase.start;` at flash_eraseall.c:156 does not parse as a DECLARATION -- `loff_t` becomes an undeclared identifier `treated as 0`, `offset` likewise, and `&offset` on the next line is then the address of an INTEGER LITERAL, which is what AN_INT_LIT (=kind 1) is and what IRLowerAddress cannot lower. PROVEN: adding `typedef long long loff_t;` alone turns the refusal into a 502192-byte object, rc=0, zero IR_UNSUPPORTED. Reduces to five lines standalone (the ticket said it had not). THE REAL C-LANE DEFECT IS THE DIAGNOSTIC: IR_UNSUPPORTED reported `in: lib/crtl/src/sys/socket.c near cmsghdr` and, in the reduced case, `near: unit builtinheap` -- locations with NO relation to the actual site, which is why this looked like a lowering gap in flash_eraseall.c for two days. crtl gap filed to the B ticket; the diagnostic is mine."
---

# What is known

Measured 2026-09-02, busybox 1.36.1 at 394 applets, binary sha256
`32a2ce1d9806`, x86-64.

```
FAIL x86_64 miscutils/flash_eraseall.c did not become an object:
  pascal26:50: error: IR_UNSUPPORTED: frontend could not lower AST node (kind 1)
  — a frontend gap, would miscompile
```

507 of 521 TUs compiled. Thirteen of the fourteen refusals are crtl gaps
(`feature-b-crtl-function-gaps-at-394-busybox-applets`,
`bug-b-crtl-host-header-fallback-leaks-BEGIN-DECLS`). This is the only one in
the compiler.

## First steps, in order

1. **Name kind 1.** The number is an AST node kind index; resolve it to its
   symbolic name before touching anything. A number standing in for a construct
   is the thing that makes this ticket look harder than it is.
2. **`PXXDBG=a.ast:<proc>`** on the wrapper TU rather than reasoning about the
   source — the compiler will say what it inferred, and line 50 of the wrapper
   is not line 50 of `flash_eraseall.c`.
3. Only then reduce. Five minimal programs failed to reproduce the last busybox
   finding standalone; do not assume this one shrinks either.

`--separate --applets "flash_eraseall"` plus `tools/busybox_diff.sh`'s wrapper
generator gives the exact TU in seconds; the whole 394-applet run is not needed
to iterate.

## Caveat on the line number

`pascal26:50` is a line in the generated wrapper, not in busybox's source. The
harness keeps `$WORK/wrap/miscutils_flash_eraseall.c` under `--keep` (and now,
since `1b2c0b5dc`, keeps its logs on any failure). Read the wrapper before
quoting a busybox line number anywhere.


## ROOT CAUSE, measured 2026-09-04 at HEAD (frankC)

```c
/* flash_eraseall.c:156-158 */
loff_t offset = erase.start;
ret = ioctl(fd, MEMGETBADBLOCK, &offset);
```

`loff_t` is a glibc GNU extension (`<sys/types.h>` under `_GNU_SOURCE`). crtl
declares only `__kernel_loff_t` (`lib/crtl/include/linux/types.h:39`). With no
such TYPE in scope the line is not a declaration at all — it parses as an
expression, and the compiler says so twice before it fails:

```
warning: undeclared identifier 'loff_t' used as value (treated as 0)
warning: undeclared identifier 'offset' used as value (treated as 0)
warning: undeclared identifier 'offset' used as value (treated as 0)
error:   IR_UNSUPPORTED: frontend could not lower AST node (kind 1)
```

`&offset` is then **the address of an integer literal**, and `AN_INT_LIT` is
kind 1 (`defs.inc:463`). `IRLowerAddress`'s tail (`ir.inc:2910`) has nowhere to
put it. **The refusal is correct.** The compiler is being handed a program that
no longer means what it says, and it declines rather than emitting something
wrong.

### Standalone reduction — five lines

```c
extern int ioctl(int, unsigned long, ...);
int main(void) {
  loff_t offset = 0;
  return ioctl(0, 1, &offset);
}
```

Control: change `loff_t` to `long long` and it compiles, rc=0.

### Proof that this is the whole blocker

Prepending `typedef long long loff_t;` to the wrapper — nothing else changed —
gives **rc=0 and a 502192-byte object**, zero `IR_UNSUPPORTED`.

## So the fourteen are FOURTEEN crtl gaps, not thirteen plus one

This ticket was the only non-crtl refusal at the 394-applet scope. It is crtl.
The rung ticket's *"the fourteenth is the only compiler finding"* is wrong, and
its corollary — that a compiler defect blocks the link — is wrong with it.
Filed to [[feature-b-crtl-function-gaps-at-394-busybox-applets]].

## THE C-LANE DEFECT THAT REMAINS — the diagnostic, not the lowering

`IR_UNSUPPORTED` reports a location with no relation to the failing construct:

| repro | reported | actual |
| --- | --- | --- |
| busybox wrapper | `lib/crtl/src/sys/socket.c` :50, `near cmsghdr` | `flash_eraseall.c:158` |
| five-line standalone | `near: unit builtinheap` | line 5 of the file |

Both point into crtl/builtin sources that compile cleanly on their own. The
node carries `ASTKind/ASTLeft/ASTRight/ASTIVal/ASTTk` (`ir.inc:2910`) but no
line, so `Error` prints wherever the parser happens to be — which by lowering
time is the runtime, not the user's code.

**This is what cost the two days, not the missing typedef.** The ticket
instructed "name kind 1" first, and that was right and took a minute; what it
could not fix is that the file and line named in the message were both false,
which sent two sessions into `flash_eraseall.c` and then into the wrapper. The
ticket's own caveat — *"`pascal26:50` is a line in the generated wrapper"* — was
itself wrong in the same way.

**An error message is an instrument.** This one does not fail to answer; it
answers confidently about the wrong file, and the three `treated as 0` warnings
that name the real cause are printed ABOVE it and read as unrelated noise.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
