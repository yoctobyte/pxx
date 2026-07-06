---
prio: 55
---
# C: address of an EXTERNAL function called through a pointer does nothing

- **Type:** bug (codegen — external proc address for indirect call). Track A/C.
- **Found:** 2026-07-07, isolating 00189 (bug-c-fnptr-to-crtl-variadic).
- **Blocks:** [[bug-c-fnptr-to-crtl-variadic]] (00189).

## Symptom
Calling an EXTERNAL (crtl) function through a function pointer produces no output
/ wrong behaviour — the indirect call goes to a wrong address. Own (internal)
functions via a pointer work.

```c
#include <stdio.h>
int (*p)(const char*) = puts;      /* or &puts, local or global */
int main(){ p("hi"); return 0; }   /* prints nothing */
```
Both local and global pointers, bare or address-of, are affected — so it is the
proc-ADDRESS of an external symbol that is wrong for an indirect call, not the
pointer-init path (that was the separate &func fix, commit caab6bde). Direct calls
to the same externals work.

## Likely site
Wherever a bare/address-of external function name is lowered to a code-address
value (IR_PROCADDR / the fn-pointer decay). An external proc's address is
probably emitted as 0 / an unrelinked slot rather than its resolved code address.

## Gate
puts/fprintf via a pointer prints; 00189 matches (dropped from pxx.skip).
