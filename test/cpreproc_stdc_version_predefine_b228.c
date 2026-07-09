/* b228: pxx must predefine __STDC_VERSION__ to a C99 value (crtl ships C99
   stdint/inttypes). Real C gates feature/type detection on it — duktape's
   duk_config.h only typedefs duk_uintptr_t etc. under __STDC_VERSION__>=199901L. */
#if !defined(__STDC_VERSION__) || (__STDC_VERSION__ < 199901L)
#error __STDC_VERSION__ must be >= 199901L (C99)
#endif
#if !defined(__STDC_HOSTED__)
#error __STDC_HOSTED__ must be defined
#endif
int main(void) { return 42; }
