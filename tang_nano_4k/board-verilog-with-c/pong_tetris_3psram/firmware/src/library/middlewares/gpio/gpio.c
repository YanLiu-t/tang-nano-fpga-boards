/*
 ******************************************************************************************
 * @file      gpio.c
 * @author    GowinSemicoductor
 * @device    Gowin_EMPU(GW1NS-4C)
 * @brief     Initializes GPIO.
 ******************************************************************************************
 */

/* Includes ------------------------------------------------------------------*/
#include "gpio.h"


/* Definitions ---------------------------------------------------------------*/

//Initializes GPIO
void gpio_init(void)
{
  GPIO_InitTypeDef GPIO_InitType;

  //Initializes GPIO pin 0
  GPIO_InitType.GPIO_Pin = GPIO_Pin_0;        //Pin 0
  GPIO_InitType.GPIO_Mode = GPIO_Mode_OUT;    //As output
  GPIO_Init(GPIO0,&GPIO_InitType);            //Initialized

  //Initializes GPIO pin 1 as input
  GPIO_InitType.GPIO_Pin = GPIO_Pin_1;        //Pin 1
  GPIO_InitType.GPIO_Mode = GPIO_Mode_IN;     //As input
	GPIO_InitType.GPIO_Int = GPIO_Int_Low_Level;//Interrupt
  GPIO_Init(GPIO0,&GPIO_InitType);            //Initialized

  //Initializes output value
  //Customized
  GPIO_SetBit(GPIO0,GPIO_Pin_0);
}
