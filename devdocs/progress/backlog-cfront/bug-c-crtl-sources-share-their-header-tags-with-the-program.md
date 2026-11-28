---
slug: bug-c-crtl-sources-share-their-header-tags-with-the-program
track: C
prio: 30
type: bug
status: backlog
created: 2026-11-28
found-by: test c_crtl_unistd_own_struct_option (bug-crtl-unistd-h-declares-getopts-struct-option)
---

# C: crtl's sources share their header tags with the program

Built in one compile (`pxx prog.c prog`, no --shared-runtime), the crtl
sources the program needs are parsed in the same run, and the C tag table is
one table that is never reset between them. A struct tag in a header that a
crtl SOURCE includes is therefore visible to the program, even when the
program never includes that header. If the program defines a struct of the
same name, it gets crtl's struct.

```c
#include <unistd.h>          /* not <getopt.h> */
struct option { int type; const char *long_name; void *value; };
int f(const struct option *o) { return o->value != 0; }
```

- `pxx --emit-obj --shared-runtime` (how Nodisx builds) compiles it.
- `pxx prog.c prog` says `no member named 'value'`. crtl's unistd.c
  implements getopt_long and includes <getopt.h>.

crtl's own internal structs already use reserved prefixes (pxx_, crtl_, __),
so the exposure is the public header tags: struct option, passwd, group,
utsname and the rest.

## What a fix needs

Scope tags to the translation unit: undo the C tag bindings (CTagRec,
CTagDepth, the undo log CTagLeaveBlock uses) at each crtl-source boundary.
Typedefs and file-scope names may share the problem, so measure them too.
The suite's one-compile rows would catch a regression.
