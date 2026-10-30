/*
 *********************************************************************************************
 * @file      delay.h
 * @author    GowinSemicoductor
 * @device    Gowin_EMPU(GW1NS-4C)
 * @brief     Delay functions.
 *********************************************************************************************
 */
 
#ifndef __DELAY_H_
#define __DELAY_H_

/* Includes ------------------------------------------------------------------*/
#include "gw1ns4c.h"


/* Definitions ---------------------------------------------------------------*/

void delay_init(void);          //Initializes
void delay_us(uint32_t nus);    //Delay microsecond
void delay_ms(uint16_t nms);    //Delay milliseconds
void delay_sec(uint16_t sec);   //Delay seconds

#endif	/* __DELAY_H_ */
