---
slug: bug-c-alignas-is-read-as-a-call
track: C
prio: 70
type: bug
status: done
owner: pxx2
created: 2026-11-26
closed: 2026-11-26
found-by: pxx2 (Nodisx dhcpcd recipe, dhcp.c's dhcp_readbpf)
tags: [cfront, layout, c11]
summary: "C11 `_Alignas(N)` / `_Alignas(type)` (and <stdalign.h>'s `alignas`, which crtl did not have) was read as a call to an undeclared function `_Alignas`. The lexer now reads it as `__attribute__((aligned(N)))` on the same token, so every declaration path that honours one honours the other; a type argument means that type's _Alignof; an argument it cannot evaluate is an error, since a guessed alignment on a member moves the rest of the struct. crtl gained <stdalign.h>. Test c_alignas26 against gcc (local, global, struct members)."
---

# `_Alignas` was read as a call

dhcpcd 10.5.2, `src/dhcp.c`:

```c
#include <stdalign.h>
...
	alignas(sizeof(struct ip *)) uint8_t buf[FRAMELEN_MAX];
```

crtl had no `<stdalign.h>` (the host's was used through the include
fallback), and cfront had no `_Alignas`: the only mention was the list of
identifiers tolerated at top level, so inside a function it became
`call to undeclared function: _Alignas`.

## Fix

`compiler/clexer.inc`, CSkipSpace: `_Alignas(...)` is consumed like an
attribute. A numeric expression (digits, parentheses, `sizeof`, `_Alignof`)
goes to CAttrAlignExprAt as `aligned(...)` does; anything else is taken as a
type name and evaluated as `_Alignof(type)`. The result sets CAttrAligned /
CAttrAlignValue, which ride the next token exactly as the attribute's do.

`lib/crtl/include/stdalign.h`: `alignas`, `alignof` and the two
`__*_is_defined` macros.

## Limit

An over-aligned LOCAL above 16 bytes is still placed at 16 (the frame is not
realigned): that is feature-c-an-over-aligned-local-is-not-aligned, the same
for the attribute spelling. The test uses 16 for its local.
