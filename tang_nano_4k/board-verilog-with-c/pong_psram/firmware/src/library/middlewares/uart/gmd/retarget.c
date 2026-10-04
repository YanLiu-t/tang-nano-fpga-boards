/*
 ******************************************************************************************
 * @file      retarget.c
 * @author    GowinSemiconductor
 * @device    Gowin_EMPU(GW1NS-4C)
 * @brief     UART printf and scanf retarget function.
 ******************************************************************************************
 */

/* Includes ------------------------------------------------------------------*/
#include "gw1ns4c.h"
#include <stdio.h>
#include <sys/stat.h>

__attribute__ ((used))  int _write (int fd, char *ptr, int len)
{
  size_t i;

  for (i=0; i<len; i++)
  {
    UART_SendChar(UART0,ptr[i]); // call character output function
  }

  return len;
}

void _close(void)
{

}

void _lseek(void)
{

}

void _read(void)
{

}

void _fstat(void)
{

}

void _kill(void)
{

}

void _isatty(void)
{

}

void _getpid(void)
{

}
