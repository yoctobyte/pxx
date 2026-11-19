/* crypt_r and struct crypt_data, libxcrypt's reentrant interface: the hash
   lands in data->output and the struct is libxcrypt's 32768 bytes. The
   Makefile row diffs this against gcc + the host's -lcrypt. */
#include <stdio.h>
#include <crypt.h>
int main(void)
{
  static struct crypt_data d;
  char *h = crypt_r("supersecretpassword", "$6$saltsalt$", &d);
  printf("%s\n%d %d\n", h ? h : "(null)", (int)sizeof d, h == d.output);
  h = crypt_r("pw", "$5$rounds=5000$abc$", &d);
  printf("%s\n", h ? h : "(null)");
  return 0;
}
