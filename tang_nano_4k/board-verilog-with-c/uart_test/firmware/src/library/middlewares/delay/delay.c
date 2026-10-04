/*
 *********************************************************************************************
 * @file      delay.c
 * @author    GowinSemicoductor
 * @device    Gowin_EMPU(GW1NS-4C)
 * @brief     Delay functions.
 *********************************************************************************************
 */

/* Includes ------------------------------------------------------------------*/
#include "delay.h"


/* Definitions ---------------------------------------------------------------*/

/* Delay variable */
static __IO uint32_t fac_us;


/**
  * @brief  Initialize delay function
  * @param  None
  * @retval None
  */
void delay_init(void)
{
  /* Configure systick */
	SysTick_CLKSourceConfig(SysTick_CLKSource_HCLK);
	
  fac_us = SystemCoreClock / (1000000U);
}

/**
  * @brief  Inserts a delay time.
  * @param  nus: Specifies the delay time length, in microsecond.
  * @retval None
  */
void delay_us(uint32_t nus)
{
  uint32_t temp = 0;
	
  SysTick->LOAD = (uint32_t)(nus * fac_us);
  SysTick->VAL = 0x00;
  SysTick->CTRL |= SysTick_CTRL_ENABLE_Msk ;
	
  do
  {
    temp = SysTick->CTRL;
  }
	while((temp & 0x01) && !(temp & (1 << 16)));

  SysTick->CTRL &= ~SysTick_CTRL_ENABLE_Msk;
  SysTick->VAL = 0x00;
}

/**
  * @brief  Inserts a delay time.
  * @param  nms: Specifies the delay time length, in milliseconds.
  * @retval None
  */
void delay_ms(uint16_t nms)
{
  delay_us(nms * 1000U);
}

/**
  * @brief  Inserts a delay time.
  * @param  sec: Specifies the delay time, in seconds.
  * @retval None
  */
void delay_sec(uint16_t sec)
{
  delay_ms(sec * 1000U);
}
