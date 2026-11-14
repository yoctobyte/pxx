/* SPDX-License-Identifier: Zlib */
/* C runtime: nl_langinfo -- glibc's C-locale answers (see <langinfo.h>). */
#include <langinfo.h>

static const char *const crtl_days[7] = {
  "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
};
static const char *const crtl_mons[12] = {
  "January", "February", "March", "April", "May", "June", "July", "August",
  "September", "October", "November", "December"
};

char *nl_langinfo(nl_item item)
{
  static char abbr[4];
  const char *s = "";
  switch (item) {
  case CODESET:    s = "ANSI_X3.4-1968"; break;
  case RADIXCHAR:  s = "."; break;
  case THOUSEP:    s = ""; break;
  case D_T_FMT:    s = "%a %b %e %H:%M:%S %Y"; break;
  case D_FMT:      s = "%m/%d/%y"; break;
  case T_FMT:      s = "%H:%M:%S"; break;
  case T_FMT_AMPM: s = "%I:%M:%S %p"; break;
  case AM_STR:     s = "AM"; break;
  case PM_STR:     s = "PM"; break;
  case YESEXPR:    s = "^[yY]"; break;
  case NOEXPR:     s = "^[nN]"; break;
  case CRNCYSTR:   s = "-"; break;
  default:
    if (item >= DAY_1 && item <= DAY_7) s = crtl_days[item - DAY_1];
    else if (item >= MON_1 && item <= MON_12) s = crtl_mons[item - MON_1];
    else if ((item >= ABDAY_1 && item <= ABDAY_7) ||
             (item >= ABMON_1 && item <= ABMON_12)) {
      const char *f = item >= ABMON_1 ? crtl_mons[item - ABMON_1]
                                      : crtl_days[item - ABDAY_1];
      /* every C-locale abbreviation is the first three letters */
      abbr[0] = f[0]; abbr[1] = f[1]; abbr[2] = f[2]; abbr[3] = 0;
      return abbr;
    }
  }
  return (char *)s;
}

char *nl_langinfo_l(nl_item item, locale_t loc)
{
  (void)loc;
  return nl_langinfo(item);
}
