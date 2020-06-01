#include <stdio.h>
#include <string.h>
#include <termios.h>

#include <string>
using namespace std;

struct speed_map
{
  string name;
  speed_t speed;
  unsigned long int baud;
};

static struct speed_map const speeds[] =
{
  {"0", B0, 0},
  {"50", B50, 50},
  {"75", B75, 75},
  {"110", B110, 110},
  {"134", B134, 134},
  {"134.5", B134, 134},
  {"150", B150, 150},
  {"200", B200, 200},
  {"300", B300, 300},
  {"600", B600, 600},
  {"1200", B1200, 1200},
  {"1800", B1800, 1800},
  {"2400", B2400, 2400},
  {"4800", B4800, 4800},
  {"9600", B9600, 9600},
  {"19200", B19200, 19200},
  {"38400", B38400, 38400},
  {"exta", B19200, 19200},
  {"extb", B38400, 38400},
#ifdef B57600
  {"57600", B57600, 57600},
#endif
#ifdef B115200
  {"115200", B115200, 115200},
#endif
#ifdef B230400
  {"230400", B230400, 230400},
#endif
#ifdef B460800
  {"460800", B460800, 460800},
#endif
#ifdef B500000
  {"500000", B500000, 500000},
#endif
#ifdef B576000
  {"576000", B576000, 576000},
#endif
#ifdef B921600
  {"921600", B921600, 921600},
#endif
#ifdef B1000000
  {"1000000", B1000000, 1000000},
#endif
#ifdef B1152000
  {"1152000", B1152000, 1152000},
#endif
#ifdef B1500000
  {"1500000", B1500000, 1500000},
#endif
#ifdef B2000000
  {"2000000", B2000000, 2000000},
#endif
#ifdef B2500000
  {"2500000", B2500000, 2500000},
#endif
#ifdef B3000000
  {"3000000", B3000000, 3000000},
#endif
#ifdef B3500000
  {"3500000", B3500000, 3500000},
#endif
#ifdef B4000000
  {"4000000", B4000000, 4000000},
#endif
  {"", 0, 0}
};

speed_t string_to_speed (const string& str)
{
  int i;

  for (i = 0; !speeds[i].name.empty() ; ++i)
    if (str == speeds[i].name)
      return speeds[i].speed;
  return (speed_t) -1;
}

unsigned long int speed_to_baud (const speed_t& speed)
{
  int i;

  for (i = 0; !speeds[i].name.empty() ; ++i)
    if (speed == speeds[i].speed)
      return speeds[i].baud;
  return 0;
}

speed_t baud_to_speed (const int& baud)
{
  int i;

  for (i = 0; speeds[i].baud != 0; ++i)
    if (baud == speeds[i].baud)
      return speeds[i].speed;
  return (speed_t) -1;
}

