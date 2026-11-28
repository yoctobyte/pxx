---
summary: "crtl: <unistd.h> declared getopt's `struct option`; git's own struct option (parse-options.h) lost its members"
type: bug
prio: 40
---

# crtl: <unistd.h> declares getopt's struct option

- **Type:** bug (crtl headers). Found 2026-11-28 building git 2.56.1 for the
  Nodisx git recipe (apply.c, `opt->value`).
- **Status:** done

## Symptom

git's parse-options.h defines its own `struct option` (type, long_name,
value, ...), and git includes <unistd.h>. pxx said `C: no member named 'value'
in this struct/union`. gcc builds it.

## Cause

glibc declares getopt_long, getopt_long_only, `struct option` and the
`*_argument` macros in <getopt.h> only. <unistd.h> has getopt, optarg and
optind. pxx's <unistd.h> declared all of them, with <getopt.h> a forwarder.
So every program that includes <unistd.h> had getopt's struct, and its own
definition was skipped.

pxx did not refuse that second definition, as gcc would have. The duplicate
body is skipped on purpose (see the open ticket
bug-c-a-struct-redefinition-in-one-scope-is-silently-ignored), so the
symptom was a missing member, far from the cause.

## Fix

getopt_long and its table now live in <getopt.h>, as in glibc. <getopt.h>
includes <unistd.h> for getopt. crtl's unistd.c, which implements
getopt_long, includes <getopt.h>. compiler/crtl_names.inc maps getopt_long
and getopt_long_only to getopt.h.

Test c_crtl_unistd_own_struct_option (row c_uopt26), against gcc. It has a
program's own struct option next to <unistd.h> and getopt from <unistd.h>. It
is built as Nodisx builds, with the runtime as its own object. Built in one
compile with the crtl sources, it still fails:
bug-c-crtl-sources-share-their-header-tags-with-the-program.
