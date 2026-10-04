/*
 *********************************************************************************************
 * @file      psram.h
 * @author    GowinSemiconductor
 * @device    Gowin_EMPU(GW1NS-4C)
 * @brief     This file contains all the functions prototypes for the PSRAM firmware library.
 *********************************************************************************************
 */

/* Define to prevent recursive inclusion -------------------------------------*/
#ifndef PSRAM_H
#define PSRAM_H

#ifdef __cplusplus
 extern "C" {
#endif

/* Includes ------------------------------------------------------------------*/
#include "gw1ns4c.h"

/* Definitions -------------------------------------------------------------------*/
//PSRAM typedef definitons
typedef struct
{
  __IO unsigned int CMD;                  /* Offset: 0x00 (R/W) PSRAM command register                */
  __IO unsigned int ADDRESS;              /* Offset: 0x04 (R/W) PSRAM address register                */
  __IO unsigned int WR_DATA0;             /* Offset: 0x08 (R/W) PSRAM write data register 0           */
  __IO unsigned int WR_DATA1;             /* Offset: 0x0C (R/W) PSRAM write data register 1           */
  __IO unsigned int WR_DATA2;             /* Offset: 0x10 (R/W) PSRAM write data register 2           */
  __IO unsigned int WR_DATA3;             /* Offset: 0x14 (R/W) PSRAM write data register 3           */
  __O  unsigned int CMD_EN;               /* Offset: 0x18 ( /W) PSRAM command enable register         */
  __IO unsigned int READ_DONE;            /* Offset: 0x1C (R/W) PSRAM read status register            */
  __I  unsigned int RD_DATA0;             /* Offset: 0x20 (R/ ) PSRAM read data register 0            */
  __I  unsigned int RD_DATA1;             /* Offset: 0x24 (R/ ) PSRAM read data register 1            */
  __I  unsigned int RD_DATA2;             /* Offset: 0x28 (R/ ) PSRAM read data register 2            */
  __I  unsigned int RD_DATA3;             /* Offset: 0x2C (R/ ) PSRAM read data register 3            */
  __I  unsigned int INIT_DONE;            /* Offset: 0x30 (R/ ) PSRAM initialization status register  */
}PSRAM_TypeDef;

//Address definitions
#define PSRAM_BASE        AHB2PERIPH_BASE /* !< PSRAM Base Address                                    */

//Type definitions
#define PSRAM             ((PSRAM_TypeDef     *) PSRAM_BASE)

/* Macros --------------------------------------------------------------------*/
#define WRITE_MODE 1    /* Write mode      */
#define READ_MODE  0    /* Read mode       */
#define CMD_ENABLE 1    /* Enable command  */
#define CMD_UNABLE 0    /* Disable command */

/* Declarations ------------------------------------------------------------------*/
/**
  * @brief Check PSRAM hardware initialization status.
  */
extern uint32_t PSRAM_Check_Init_Status(void);

/**
  * @brief Set PSRAM read/write mode.
  */
extern uint32_t PSRAM_Mode_Set(uint32_t mode);

/**
  * @brief Set PSRAM address, save data into this address.
  */
extern uint32_t PSRAM_Address_Set(uint32_t address);

/**
  * @brief Read data from PSRAM buffer.
  */
extern uint32_t PSRAM_Read_Data_Buff(uint32_t *Buff,uint32_t address);

/**
  * @brief Enable PSRAM command.
  */
extern void PSRAM_Cmd_Enable(void);

/**
  * @brief The flag of read PSRAM done.
  */
extern uint32_t PSRAM_Read_Done_Flag(void);

/**
  * @brief Clear the flag of read PSRAM done.
  */
extern void PSRAM_Clear_Read_Done_Flag(void);

/**
  * @brief Write data into PSRAM buffer, 4 word is a cycle.
  */
extern uint32_t PSRAM_Write_Data_Buff(uint32_t *Buff,uint32_t address);

/**
  * @brief Disable PSRAM command.
  */
extern void PSRAM_Cmd_Unable(void);

/**
  * @brief Write a package data into PSRAM.
  */
extern uint32_t PSRAM_Write_Data_Package(uint32_t *Buff,uint32_t address,uint32_t num);

/**
  * @brief Read a package data from PSRAM.
  */
extern uint32_t PSRAM_Read_Data_Package(uint32_t *Buff,uint32_t address,uint32_t num);

#ifdef __cplusplus
}
#endif

#endif /* PSRAM_H */

/*************************GowinSemiconductor*****END OF FILE*********************/
