/* C character/string escape sequences \a \b \f \v were not decoded by the C
   lexer — it returned the literal letter (e.g. '\f' == 'f' == 102 instead of
   12). lua's lexer has `case '\f':` (form feed); with '\f' mis-lexed as 'f',
   the case matched the letter 'f', so every Lua identifier beginning with 'f'
   (`for`, `false`, `function`) had its first char consumed -> "for" lexed as
   "or" -> reserved-word table mapped it to TK_OR -> control flow broke. */

extern long __pxx_write(int, const void *, unsigned long);

int main(void) {
  /* char-literal forms */
  if ((int)'\a' != 7)  return 1;
  if ((int)'\b' != 8)  return 2;
  if ((int)'\f' != 12) return 3;
  if ((int)'\v' != 11) return 4;
  if ((int)'\n' != 10) return 5;
  if ((int)'\t' != 9)  return 6;
  if ((int)'\r' != 13) return 7;
  if ((int)'\0' != 0)  return 8;
  if ((int)'f'  != 102) return 9;   /* plain letter unaffected */

  /* string-literal forms keep the same bytes */
  {
    const char *s = "\a\b\f\v";
    if (s[0] != 7 || s[1] != 8 || s[2] != 12 || s[3] != 11) return 10;
  }
  /* a switch on '\f' must NOT match the letter 'f' */
  switch ('f') {
    case '\f': return 11;     /* would fire if '\f' == 'f' (the bug) */
    default: break;
  }
  return 42;
}
