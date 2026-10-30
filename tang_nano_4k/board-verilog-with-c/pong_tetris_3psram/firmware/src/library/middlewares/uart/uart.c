/*
 ******************************************************************************************
 * @file      uart.c
 * @author    GowinSemicoductor
 * @device    Gowin_EMPU(GW1NS-4C)
 * @brief     Initializes UART.
 ******************************************************************************************
 */

/* Includes ------------------------------------------------------------------*/
#include "uart.h"


/* Definitions ---------------------------------------------------------------*/

//Initializes UART
//baudrate
//tx          : Tx
//rx          : Rx
//tx_intr     : Tx interrupt
//rx_intr     : Rx interrupt
//tx_ovr_intr : Tx overflow interrupt
//rx_ovr_intr : Rx overflow interrupt
void uart_init(UART_TypeDef* UARTx,
               uint32_t baudrate,
               uint32_t tx,
               uint32_t rx,
               uint32_t tx_intr,
               uint32_t rx_intr,
               uint32_t tx_ovr_intr,
               uint32_t rx_ovr_intr)
{
  UART_InitTypeDef UART_InitStruct;

  UART_InitStruct.UART_Mode.UARTMode_Tx = (FunctionalState)tx;          //Tx
  UART_InitStruct.UART_Mode.UARTMode_Rx = (FunctionalState)rx;          //Rx
  UART_InitStruct.UART_Int.UARTInt_Tx   = (FunctionalState)tx_intr;     //Tx interrupt
  UART_InitStruct.UART_Int.UARTInt_Rx   = (FunctionalState)rx_intr;     //Rx interrupt
  UART_InitStruct.UART_Ovr.UARTOvr_Tx   = (FunctionalState)tx_ovr_intr; //Tx overflow interrupt
  UART_InitStruct.UART_Ovr.UARTOvr_Rx   = (FunctionalState)rx_ovr_intr; //Rx overflow interrupt
  UART_InitStruct.UART_Hstm = DISABLE;
  UART_InitStruct.UART_BaudRate = baudrate;

  UART_Init(UARTx,&UART_InitStruct);
}

void _putchar(char character)
{
	UART_SendChar(UART0, character);
}
