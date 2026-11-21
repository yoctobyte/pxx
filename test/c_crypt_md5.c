/* crypt(3) MD5-crypt, "$1$", against libxcrypt on the same inputs.
 *
 * Rows: salts of 0 to 8 characters, one longer than 8 (truncated), one ended
 * by '$', keys around the 16-byte digest length (the alt-digest loop runs
 * once, exactly, and more than once), the empty key, and one longer than an
 * MD5 block (64 bytes). The result is fed back in, as /etc/shadow stores it.
 * toybox's `mkpasswd -m md5` row is the first one.
 * pxx: lib/crtl/src/crypt.c. gcc: link with -lcrypt.
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
    "$1$abcdefgh", "$1$", "$1$a", "$1$abc$", "$1$abcdefghijkl", "$1$saltsalt$ignored",
  };
  static const char *keys[] = {
    "password", "", "0123456789abcdef", "0123456789abcdefg",
    "a much longer key that runs past one md5 block of sixty-four bytes, twice over",
  };
  unsigned i, k;
  for (i = 0; i < sizeof settings / sizeof settings[0]; i++)
    for (k = 0; k < sizeof keys / sizeof keys[0]; k++)
      row(keys[k], settings[i]);
  return 0;
}
