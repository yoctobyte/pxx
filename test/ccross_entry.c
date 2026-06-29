/* Cross-target C program entry smoke. The C frontend emits its own entry stub
   (save sp, hand main argc/argv, call main, exit_group main's return). This
   guards that the stub is target-correct (was hardcoded x86-64 bytes, which
   crashed on i386/arm/etc). Pure constant return -> exercises only the entry +
   exit path, independent of the deeper C call/arith cross gaps. Exit code 42. */
int main(void) {
    return 42;
}
