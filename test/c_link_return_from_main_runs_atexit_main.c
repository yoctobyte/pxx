/* pascal26 --link: RETURNING from main is exit(main's value) (C11 5.1.2.2.3),
   so atexit handlers run and stdio is flushed. The handlers are registered in
   the OTHER object (c_link_return_from_main_runs_atexit_part.c), the shape a
   multi-object program has. The synthesised _start used to go straight to the
   exit syscall: nothing below "main returns" was printed (found building mksh
   for Nodisx). With an argument, main calls exit() itself instead: same output.
   Expected output and status are gcc's. */
#include <stdio.h>
#include <stdlib.h>
void register_handlers(void);
int main(int argc, char **argv) {
  (void)argv;
  register_handlers();
  printf("main returns 3\n");      /* buffered when stdout is a pipe */
  if (argc > 1) exit(3);
  return 3;
}
