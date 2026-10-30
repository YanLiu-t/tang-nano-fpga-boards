/*
 ******************************************************************************************
 * @file      uart.h
 * @author    GowinSemicoductor
 * @device    Gowin_EMPU(GW1NS-4C)
 * @brief     Initializes UART.
 ******************************************************************************************
 */

#ifndef __UART_H_
#define __UART_H_

/* Includes ------------------------------------------------------------------*/
#include "gw1ns4c.h"


/* Definitions ---------------------------------------------------------------*/

void uart_init(UART_TypeDef* UARTx,    //UARTx
               uint32_t baudrate,      //Baudrate
               uint32_t tx,            //Tx
               uint32_t rx,            //Rx
               uint32_t tx_intr,       //Tx interrupt
               uint32_t rx_intr,       //Rx interrupt
               uint32_t tx_ovr_intr,   //Tx overflow interrupt
               uint32_t rx_ovr_intr);  //Rx overflow interrupt
void _putchar(char character);

#endif	/* __UART_H_ */
