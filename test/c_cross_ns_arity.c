/* A C declaration must win over an unrelated Pascal routine that merely shares
   its name case-insensitively. `time` collides with sysutils' parameterless
   `function Time: TDateTime`; before the fix the call bound to the Pascal
   routine, so `now` was never written and the probe returned 0 where gcc
   returns 1 — a caller reading uninitialised memory behind a plausible return
   value. Declared by hand rather than via <time.h> on purpose: the header
   works around the collision with `#define time(t) __crtl_time(t)`, which
   would hide exactly the path under test.
   bug-cfront-c-name-binds-to-pascal-routine-at-wrong-arity */

extern long long time(long long *t);

int cns_probe_time(void) {
  long long now = 0;
  long long r = time(&now);
  return (now != 0) && (now == r);   /* gcc: 1 */
}
