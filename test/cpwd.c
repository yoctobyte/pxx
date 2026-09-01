/* /etc/passwd lookups against the gcc oracle.
 *
 * crtl had no pwd.h, so busybox's libbb/bb_pwd.c, libbb/get_shell_name.c and
 * ash's `~user' expansion did not compile. Found by attempting the target
 * (feature-c-corpus-busybox-multi-applet).
 *
 * WHAT IS COMPARED, AND THE ONE PLACE THIS CAN LEGITIMATELY DIVERGE.
 * crtl reads /etc/passwd and nothing else; glibc consults nsswitch.conf and may
 * answer from LDAP, systemd or a network directory. So the two agree only for
 * users that really are in the file. `root' is the one entry that is in
 * /etc/passwd on every system this could run on, so it is the row compared
 * against gcc. A machine whose users come from a directory service would make a
 * getpwuid(getuid()) comparison fail for a reason that is not a defect, which
 * is why that row prints only STRUCTURAL facts (found / not found, non-empty)
 * and not the values.
 *
 * Also asserted: a uid that cannot exist returns NULL rather than a stale
 * pointer to the previous entry, which is the failure mode of a lookup that
 * forgets to clear its static on the not-found path.
 */
#include <pwd.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(void) {
  struct passwd *r, *n;

  r = getpwnam("root");
  printf("root found=%d\n", r != 0);
  if (r) {
    printf("root name=%s uid=%d gid=%d dir=%s\n",
           r->pw_name, (int)r->pw_uid, (int)r->pw_gid, r->pw_dir);
    printf("root shell nonempty=%d\n", r->pw_shell && r->pw_shell[0] != '\0');
  }

  /* Same entry by uid must agree with the same entry by name. */
  r = getpwuid(0);
  printf("uid0 found=%d name=%s\n", r != 0, r ? r->pw_name : "(null)");

  /* Not found must be NULL, not the last successful lookup. */
  n = getpwnam("no.such.user.exists.hopefully");
  printf("missing name=%d\n", n == 0);
  n = getpwuid((uid_t)4000000000u);
  printf("missing uid=%d\n", n == 0);

  /* Structural only -- values depend on who is running this and on whether the
     host resolves users through something other than /etc/passwd. */
  r = getpwuid(getuid());
  printf("self structural=%d\n", r == 0 || (r->pw_name && r->pw_name[0] != '\0'));
  return 42;
}
