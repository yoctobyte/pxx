---
slug: bug-c-line-in-a-multi-line-macro-call-is-its-last-line
track: C
prio: 45
type: bug
status: open
found: 2026-11-28
found-by: pxx2 (pxx-built libwlroots in Panorama: log lines said sockets.c:49, gcc's 47)
owner:
summary: "__LINE__ inside a function-like macro invocation that spans lines expands to the line of the closing parenthesis; gcc gives the line of the macro name. The preprocessor joins the physical lines of an unbalanced invocation with spaces (cpreproc.inc, the parenthesis join) and keeps only CPCurLine, the last line consumed, so every log macro written over several lines (wlroots' wlr_log_errno, most projects' logging) reports a different line from the gcc build."
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

Likely fix: when the join appends a physical line, record the offset in
CPrepLine where it starts and its line number. When CPExpandRange at top
level meets a macro name, take that name's line from the table and use it
for `__LINE__` for the whole expansion, nested ones included. A
`__LINE__` written directly in the arguments needs checking against gcc too.

Repro: /data/tmp/testtmp/ln2.c (scratch); the three-line table above.
