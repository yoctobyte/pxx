/* clearenv() removes every environment variable. busybox's `env -i` calls it,
   and coreutils/env.c would not compile at all without the declaration --
   which is how this was found (feature-c-corpus-busybox-multi-applet).

   ROW 1 IS THE WHOLE TEST, AND IT HAS TO COME FIRST.

   pxx_env_load() is LAZY. An implementation that sets only the length to 0
   leaves the buffer marked NOT loaded, and the next getenv() re-reads
   /proc/self/environ and resurrects everything clearenv() just removed.
   Emptied and loaded are two facts, not one.

   That bug is only observable while the buffer is still COLD, so the check
   must be the first environment call the program makes. The first cut of this
   file opened with `getenv("PATH")` to show the variable was there to begin
   with -- and that read warmed the buffer, so every later row passed against
   the broken implementation too. Verified by building this file against a
   deliberately naive clearenv: identical output, all six rows.

   The cost is that this program cannot ALSO show PATH being visible before the
   clear -- observing it is precisely what destroys the condition under test.
   That is what row 2 is for: it is a variable this program set itself, so it
   proves the buffer is live rather than merely empty, without a prior read. */
#include <stdio.h>
#include <stdlib.h>

int main(void) {
  int rc;

  /* 1: COLD. Nothing has touched the environment yet. PATH is set in any
     environment this test runs in, so a 1 here means it came back. */
  rc = clearenv();
  printf("1 %d %d\n", rc, getenv("PATH") != 0);

  /* 2: the buffer still works -- clearenv empties, it does not poison. Also
     shows the space was truncated rather than left mangled. */
  setenv("PXX_AFTER", "back", 1);
  printf("2 %s\n", getenv("PXX_AFTER") ? getenv("PXX_AFTER") : "(null)");

  /* 3: a second clearenv removes that too, and is not an error.
     SEQUENCED DELIBERATELY: written as
     `printf("%d %d", clearenv(), getenv("PXX_AFTER") != 0)` both pxx and gcc
     printed `0 1`, agreeing, and both evaluating getenv BEFORE clearenv.
     Argument evaluation order is UNSPECIFIED in C, so that row asserted
     nothing and would flip the day either compiler reordered. */
  rc = clearenv();
  printf("3 %d %d\n", rc, getenv("PXX_AFTER") != 0);

  /* 4: and it is still usable after two clears */
  setenv("PXX_LAST", "ok", 1);
  printf("4 %s\n", getenv("PXX_LAST") ? getenv("PXX_LAST") : "(null)");
  return 0;
}
