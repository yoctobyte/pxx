/* What getgrgid/getgrnam return survives getgrouplist, and neither of them
   moves a getgrent walk the caller has in progress. The oracle is gcc, run
   on the same box (the answers depend on its /etc/group).

   toybox `id root' (bug-c-toybox-test-suite-failures) keeps getgrgid(0) and
   calls getgrouplist before printing it. crtl's getgrouplist walked the file
   through getgrent, the same static struct, so id printed the LAST line of
   /etc/group: gid=117(direwolf) on plexus. */
#include <grp.h>
#include <pwd.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
  struct group *g = getgrgid(0);
  char before[64], first[64];
  gid_t list[256];
  int n = 256, i;
  struct passwd *pw;

  if (!g) { printf("no group 0\n"); return 0; }
  snprintf(before, sizeof before, "%s:%d", g->gr_name, (int)g->gr_gid);
  pw = getpwuid(0);
  getgrouplist(pw ? pw->pw_name : "root", 0, list, &n);
  printf("getgrgid(0) before getgrouplist: %s\n", before);
  printf("same pointer after getgrouplist:  %s:%d\n", g->gr_name, (int)g->gr_gid);

  g = getgrnam(before[0] ? strtok(before, ":") : "root");
  printf("getgrnam: %s\n", g ? g->gr_name : "NULL");

  /* a getgrent walk with lookups in the middle keeps its place */
  setgrent();
  g = getgrent();
  snprintf(first, sizeof first, "%s", g ? g->gr_name : "NULL");
  getgrgid(0);
  getgrnam("root");
  n = 256;
  getgrouplist("root", 0, list, &n);
  for (i = 0; (g = getgrent()) != 0; i++) { }
  endgrent();
  printf("walk: first=%s, then %d more entries\n", first, i);
  return 0;
}
