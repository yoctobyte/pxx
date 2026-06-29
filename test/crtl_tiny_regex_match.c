/* Drop-in compile + run of kokke/tiny-regex-c via the C frontend.
   Unity-includes re.c (the library has no main of its own) and asserts the
   known POSIX cases. Exits non-zero on any mismatch so the devtest dashboard
   and `make` can gate on it. Compile with:
     pascal26 -Ilib/crtl/include -Ilibrary_candidates/tiny-regex-c \
              test/crtl_tiny_regex_match.c <out>
*/
#include <stdio.h>
#include "re.c"

static int fails = 0;

static void check(const char* pat, const char* text,
                  int want_idx, int want_len) {
    int len = 0;
    int idx = re_match(pat, text, &len);
    int ok = (idx == want_idx) && (idx < 0 || len == want_len);
    if (!ok) {
        printf("FAIL  /%s/ on \"%s\": got idx=%d len=%d want idx=%d len=%d\n",
               pat, text, idx, len, want_idx, want_len);
        fails++;
    }
}

int main(void) {
    check("[0-9]+", "abc123xyz", 3, 3);   /* digits */
    check("^hello", "hello world", 0, 5); /* anchor hit */
    check("^hello", "say hello", -1, 0);  /* anchor miss */
    check("\\w+@\\w+", "x me@host y", 2, 7); /* email-ish */
    check("a.c", "xxabcyy", 2, 3);        /* dot */
    if (fails == 0) printf("tiny-regex: all cases pass\n");
    return fails;
}
