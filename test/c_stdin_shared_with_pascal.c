/* ONE STDIN, THREE READERS. crtl's stdin read fd 0 behind the back of
   Pascal's two readers: a byte Pascal's Eof had peeked was invisible to a
   following getchar, and a C ungetc on stdin was invisible to ReadLn. Fed
   "abc\ndef\nghi\njk\n"; every step names the byte it must see.
   bug-c-crtl-stdin-and-pascal-input-do-not-share-a-peeked-byte */
#include <stdio.h>
#include "c_stdin_shared_with_pascal_unit.pas"

int main(void) {
  char buf[32];
  int c;
  printf("eof=%d\n", PEof());           /* console peeks 'a' */
  c = getchar();
  printf("getchar=%c\n", c);            /* a: was lost */
  ungetc('X', stdin);
  PReadLn();                            /* P:Xbc: the X was invisible */
  printf("eofi=%d\n", PEofInput());     /* textfile peeks 'd' */
  c = getchar();
  printf("getchar=%c\n", c);            /* d */
  ungetc(c, stdin);
  if (fgets(buf, sizeof buf, stdin)) printf("fgets=%s", buf);   /* def */
  ungetc('Y', stdin);
  PReadLnInput();                       /* PI:Yghi */
  printf("eofi=%d\n", PEofInput());     /* textfile peeks 'j' */
  c = getchar();
  printf("getchar=%c\n", c);            /* j, from textfile */
  ungetc(c, stdin);                     /* to the console's peek slot */
  PReadLn();                            /* P:jk */
  printf("eof=%d\n", PEof());           /* 1 */
  c = getchar();
  printf("end=%d\n", c);                /* -1 */
  return 0;
}
