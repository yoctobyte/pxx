/* SPDX-License-Identifier: Zlib */
/* Regression b239 (feature-c-cmdline-define-flag, Track C): the C driver honours
   `-D<name>[=<value>]` and `-U<name>`. Built with `-DGUARD=42 -DON -UOFFME`.
   Exercises: -D with a value, -D defaulting to 1, and -U removing a name.
   Exit 42 = pass. */
#ifndef ON
#error "-DON did not define ON"
#endif
#ifdef OFFME
#error "-UOFFME did not remove OFFME"
#endif
#if ON != 1
#error "-DON should default to 1"
#endif
int main(void) {
#if defined(GUARD) && GUARD == 42
  return GUARD;
#else
  return 1;
#endif
}
