/* crypt(3) SHA-crypt, "$5$" and "$6$", against libxcrypt on the same inputs.
 *
 * Rows: the spec's own salt/round edge cases. That covers the default rounds,
 * an explicit rounds=, a salt longer than 16 characters (truncated), an empty
 * key, and
 * a key longer than one digest (the B-stretch and P-stretch loops run more
 * than once). The full setting string is passed back in, as /etc/shadow
 * stores it, to show that crypt(key, crypt(key, salt)) reproduces itself.
 *
 * TWO DELIBERATE DIFFERENCES FROM libxcrypt ARE NOT ROWS, because there the
 * oracle disagrees with the spec rather than with us: rounds below 1000
 * (libxcrypt answers the failure token "*0", while the spec, glibc and musl
 * clamp to 1000, and crtl clamps), and "$1$" MD5-crypt (libxcrypt has it,
 * crtl answers NULL/EINVAL, see crypt.c).
 *
 * pxx: lib/crtl/src/crypt.c. gcc: link with -lcrypt.
 * Found building dropbear (svr-authpasswd.c).
 */
#include <stdio.h>
#include <string.h>
#include <crypt.h>

static void row(const char *key, const char *setting)
{
  const char *h = crypt(key, setting);
  char copy[160];
  const char *again;
  if (!h) { printf("NULL\n"); return; }
  strcpy(copy, h);
  again = crypt(key, copy);
  printf("%s %s\n", copy, again && strcmp(again, copy) == 0 ? "stable" : "UNSTABLE");
}

int main(void)
{
  static const char *settings[] = {
    "$5$saltstring", "$6$saltstring",
    "$5$rounds=10000$saltstringsaltstring", "$6$rounds=10000$saltstringsaltstring",
    "$5$rounds=1400$anotherlongsaltstring", "$6$rounds=1400$anotherlongsaltstring",
  };
  static const char *keys[] = {
    "Hello world!", "",
    "a very much longer text to encrypt.  This one even stretches over more"
    "than one line.",
  };
  unsigned i, k;
  for (i = 0; i < sizeof settings / sizeof settings[0]; i++)
    for (k = 0; k < sizeof keys / sizeof keys[0]; k++)
      row(keys[k], settings[i]);
  return 0;
}
