/* C preprocessor `#if` constant-expression arithmetic. The evaluator previously
   had NO additive/multiplicative/shift/bitwise levels — trailing operators were
   silently dropped, so `defined(A)+defined(B)+...==0` (sqlite's
   SQLITE_SYSTEM_MALLOC auto-select) and `FLAGS&MASK` / `1<<n` mis-evaluated. A
   leading-`0` operand made `0 + x` fold to 0 (the `+ x` was ignored).
   Each enabled block adds to the exit code; total must be 42. */

/* defined()-sum == 0  -> none defined -> +10  (the sqlite idiom) */
#if defined(QQ_A) + defined(QQ_B) + defined(QQ_C) + defined(QQ_D) == 0
# define ADD_A 10
#else
# define ADD_A 0
#endif

/* additive with a leading 0 operand -> +6 */
#if 0 + 6 == 6
# define ADD_B 6
#else
# define ADD_B 0
#endif

/* multiplicative + additive precedence: 2*3+4 == 10 -> +8 */
#if 2 * 3 + 4 == 10
# define ADD_C 8
#else
# define ADD_C 0
#endif

/* shift and bitwise-and: (1<<3) | 2 == 10, (10 & 6) == 2 -> +9 */
#if ((1 << 3) | 2) == 10 && (10 & 6) == 2
# define ADD_D 9
#else
# define ADD_D 0
#endif

/* nested in a real config-style chain: SQLITE_DQS default 3 -> (3&1)==1 -> +9 */
#define MY_DQS 3
#if (MY_DQS & 1) == 1
# define ADD_E 9
#else
# define ADD_E 0
#endif

int main(void) {
  return ADD_A + ADD_B + ADD_C + ADD_D + ADD_E; /* 10+6+8+9+9 = 42 */
}
