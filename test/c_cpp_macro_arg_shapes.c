/* Four preprocessor shapes that busybox's own build uses on every translation
   unit, none of which worked. They are one test because they were one attempt
   -- compiling busybox's 52 libbb/coreutils sources as SEPARATE OBJECTS with
   busybox's real command line -- and because two of them only surface together.

   1. `, ## __VA_ARGS__` (GNU comma deletion). include/libbb.h:1354 is
        #define getopt32long(argv,optstring,longopts,...) \
                getopt32(argv,optstring,##__VA_ARGS__)
      called with no trailing arguments by `ls` and `mkdir`. Without the
      deletion the expansion is `getopt32(argv,"m:pv",)`.

   2. A DIRECTIVE INSIDE A MACRO INVOCATION'S ARGUMENT LIST. coreutils/mkdir.c
      puts `# if ENABLE_SELINUX ... # endif` between two arguments. The
      preprocessor used to emit the half-collected line and give up, leaving
      the invocation's `(` unclosed -- so the error landed on the CALL and
      never mentioned the directive. Undefined per C 6.10.3/11, and accepted by
      gcc, clang and tcc alike.

   3. `-include <file>` (row `forced`). Makefile.flags puts
      `-include include/autoconf.h` on all ~145 of busybox's translation units;
      without it not one of them compiles from its own build system. The `line`
      row is the half that is easy to get wrong: a forced include must not
      shift the primary source's line numbers, which rules out the obvious
      implementation of prepending it to the text. Its expected value is a
      LITERAL line number, so moving code in this file moves the answer -- that
      is deliberate, and the number is the point.

   4. An ABSOLUTE path in `#include "..."`, which a generated build file writes
      when it knows where its config header lives. It used to be concatenated
      onto the including file's directory and reported as not found. Covered by
      the Makefile row that passes an absolute -include, which resolves through
      the same code path.

   The CONTROL rows are the other direction: the same macro with a NON-empty
   variadic argument, and a directive whose condition is TRUE, so a fix that
   simply dropped variadic arguments or dropped all conditional text would not
   pass.
   feature-c-corpus-busybox-multi-applet */
#include <stdio.h>

#define OFF 0
#define ON  1
#define IF_OFF(...)
#define IF_ON(...) __VA_ARGS__

/* `drop` is never used by the body, exactly as busybox's getopt32long drops
   its longopts argument when long options are configured out. */
#define CALL(base, drop, ...) sum(base, ##__VA_ARGS__)

static int sum(int base) { return base; }
static int sum2(int base, int extra) { return base + extra; }
#define sum(...) SUM_PICK(__VA_ARGS__, sum2, sum1)(__VA_ARGS__)
#define SUM_PICK(_1, _2, N, ...) N
#define sum1(a) (a)

int main(void)
{
  /* 1: comma deleted (no variadic args) vs kept (one variadic arg) */
  printf("swallow %d\n", CALL(10, "longopts"));
  printf("keep    %d\n", CALL(10, "longopts", 5));

  /* 2: a FALSE directive between arguments -- the dropped arm contributes
        nothing and the call still closes */
  printf("dirfalse %d\n", CALL(20, "longopts"
# if OFF
        , 999
# endif
        ));

  /* 2b, CONTROL: a TRUE directive between arguments contributes its text */
  printf("dirtrue %d\n", CALL(30, "longopts"
# if ON
        , 9
# endif
        ));

  /* 2c: mkdir.c's exact shape -- a directive inside the argument list AND an
         empty variadic tail, so the comma deletion happens after the join */
  printf("mkdirshape %d\n", CALL(40, "m:pv" IF_OFF("Z:")
        "mode\0"    "m"
# if OFF
        "context\0" "Z"
# endif
        IF_ON()));

  /* 3: -include, and the line number below must still be its own */
  printf("forced %d\n", FORCED_BY_MINUS_INCLUDE);
  printf("line %d\n", __LINE__);
  return 0;
}
