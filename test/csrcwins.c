/* The C unit that sits BESIDE the program. There is also a csrcwins.pas in
   test/csrcwins_units, reached by -Fu, and this file must win: a .c or .h next
   to the source you are compiling is an explicit local choice, which is why
   bug-a-a-c-include-path-captures-a-pascal-uses-and-emits-a-dynamic-import
   moved the SEARCH-ROOT C probe behind the whole Pascal chain and deliberately
   left the source-directory one where it was.
   111 and 222 rather than a 0/1: either number is a real answer from a real
   unit, so the row cannot pass on a default. */
int CWinsPick(void) { return 111; }
