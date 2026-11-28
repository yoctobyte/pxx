---
slug: bug-c-line-in-a-multi-line-macro-call-is-its-last-line
track: C
prio: 45
type: bug
status: done
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (pxx-built libwlroots in Panorama: log lines said sockets.c:49, gcc's 47)
owner: pxx2
summary: "FIXED: matches gcc now. __LINE__ inside a function-like macro invocation that spans lines expands to the line of the closing parenthesis; gcc gives the line of the macro name. The preprocessor joins the physical lines of an unbalanced invocation with spaces (cpreproc.inc, the parenthesis join) and keeps only CPCurLine, the last line consumed, so every log macro written over several lines (wlroots' wlr_log_errno, most projects' logging) reports a different line from the gcc build."
---

# `__LINE__` in a multi-line macro call is its last line

```c
#define LOG(fmt, ...) printf("[%d] " fmt "\n", __LINE__, ##__VA_ARGS__)
  LOG("two %d",      /* line 6 */
      2);            /* line 7 */
```

gcc prints `[6]`, pxx `[7]`; a three-line nested call gives 8 against 10.
C leaves which line unspecified, so neither is wrong by the standard. gcc
and clang agree, though, and comparing pxx's logs with a gcc build's
(Panorama's ERROR lines) turns it into noise.

## Fixed

gcc's rule, measured (gcc 15.2): `__LINE__` in a macro **body** is the
line of the macro's **name**, also when its `(` is on a later line. One
written in an **argument** keeps its own physical line (`PAIR(__LINE__,` /
`__LINE__)` gives 20 21), and so does an object-like macro used as an
argument (`HERE`). clang uses the closing parenthesis for the body case,
which is what pxx did; Panorama's oracle is gcc, so pxx follows gcc.

cpreproc.inc: the join records where each physical line starts in
CPrepLine (CPJoinAppend / CPJoinReset, CPJoinLineAt). The top-level pass
(CPExpandPrepLine) and the pre-expansion of arguments taken from that text
are "mapped" (CPCurMapped / CPNextMapped, since a level number cannot tell
argument text from a body rescan). Each identifier they reach sets
CPTokLine, and `__LINE__` reads it. After an argument's pre-expansion,
CPTokLine goes back to the invocation's line for the body. Directive
lines and -g line markers are unchanged.

Test test/c_line_multiline_call.c (c_linemulti26), against gcc: multi-line
calls, nested variadic macros, `__LINE__` and an object macro in
arguments, a name and its `(` on different lines, a non-macro call, two
calls on one line. Panorama's all-pxx ERROR lines are now identical to
the gcc build's (sockets.c:47).
