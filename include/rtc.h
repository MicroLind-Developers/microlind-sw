#ifndef _RTC_H_
#
//-----------------------------------------------------------------
// Real Time Clock (RTC)
// Register Map $F418 - $F41F
// Memory Map   None
//-----------------------------------------------------------------
#define RTC_BASE                    (IO_BASE + 18)
#define RTC_YEAR                    (RTC_BASE + 0)
#define RTC_MONTH                   (RTC_BASE + 1)
#define RTC_DAY                     (RTC_BASE + 2)
#define RTC_HOUR                    (RTC_BASE + 3)
#define RTC_MINUTE                  (RTC_BASE + 4)
#define RTC_SECOND                  (RTC_BASE + 5)