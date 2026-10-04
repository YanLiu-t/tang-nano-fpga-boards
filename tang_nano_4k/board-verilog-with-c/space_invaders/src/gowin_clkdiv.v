//============================================================================
// GOWIN CLKDIV - Divisore di clock
//============================================================================
//
// CHE COS'È UN CLKDIV?
// È un divisore di frequenza hardware dedicato dell'FPGA Gowin.
// A differenza di un divisore fatto con flip-flop, questo primitivo:
// - Ha basso jitter (variazione temporale)
// - Mantiene il clock allineato con la sorgente
// - Usa risorse dedicate, non logica generale
//
// NEL NOSTRO PROGETTO:
// - Input: 250 MHz (dal PLL)
// - DIV_MODE = 5
// - Output: 250 / 5 = 50 MHz (pixel clock)
//
// PERCHÉ 50 MHz?
// Per 1024x600 @ 60Hz servono:
// - Pixel totali = (1024 + 48 + 96 + 144) × (600 + 3 + 10 + 11) = 1312 × 624
// - Pixel/secondo = 1312 × 624 × 60 = 49,136,640 ≈ 50 MHz
//
// PERCHÉ USARE CLKDIV INVECE DI UN CONTATORE?
// 1. Un contatore modulo-5 con flip-flop userebbe logica aggiuntiva
// 2. Il timing non sarebbe così preciso
// 3. Il CLKDIV è ottimizzato per questa funzione specifica
//
//============================================================================

// Copyright originale Gowin
//Copyright (C)2014-2024 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: IP file
//GOWIN Version: V1.9.9
//Part Number: GW1NR-LV9QN88PC6/I5
//Device: GW1NR-9C
//Created Time: 2024

module Gowin_CLKDIV (clkout, hclkin, resetn);

//============================================================================
// PORTE DEL MODULO
//============================================================================

// Clock di output diviso
// Frequenza = hclkin / DIV_MODE = 250 / 5 = 50 MHz
output clkout;

// Clock di input ad alta frequenza
// Nel nostro caso: 250 MHz dal PLL
input hclkin;

// Reset attivo basso
// Quando resetn=0, il divisore si resetta
// Il clock riparte sincronizzato quando resetn torna a 1
input resetn;

//============================================================================
// SEGNALI INTERNI
//============================================================================

wire gw_gnd;  // Costante 0 per ingressi non usati

assign gw_gnd = 1'b0;

//============================================================================
// ISTANZA DEL PRIMITIVO CLKDIV
//============================================================================
// CLKDIV è una primitiva hardware dedicata dell'FPGA Gowin.
// Non è codice sintetizzabile, ma un blocco fisico del chip.

CLKDIV clkdiv_inst (
    .CLKOUT(clkout),   // Clock di output (50 MHz)
    .HCLKIN(hclkin),   // Clock di input (250 MHz)
    .RESETN(resetn),   // Reset attivo basso
    .CALIB(gw_gnd)     // Calibrazione (non usata)
);

//============================================================================
// PARAMETRI DEL DIVISORE
//============================================================================

// Fattore di divisione
// Valori possibili: 2, 3.5, 4, 5, 8, 16, 32, 64, 128
// Output = Input / DIV_MODE
defparam clkdiv_inst.DIV_MODE = "5";  // 250 MHz / 5 = 50 MHz

// Global Set/Reset Enable
// Se "true", il divisore risponde al GSR globale dell'FPGA
// Lo mettiamo "false" per controllo esplicito con resetn
defparam clkdiv_inst.GSREN = "false";

endmodule //Gowin_CLKDIV

//============================================================================
// NOTE AGGIUNTIVE
//============================================================================
//
// ALTRI VALORI DI DIV_MODE:
// - "2": Output = Input / 2
// - "3.5": Output = Input / 3.5
// - "4": Output = Input / 4
// - "5": Output = Input / 5
// - "8": Output = Input / 8
// - ...fino a "128"
//
// NOTA SUL VALORE 3.5:
// Il divisore può fare divisioni non intere! Questo è utile per ottenere
// frequenze particolari, ma il duty cycle non sarà esattamente 50%.
//
// ESEMPIO PER ALTRA RISOLUZIONE:
// Per 720p (1280x720 @ 60Hz) serve pixel clock ≈ 74.25 MHz
// - PLL output = 371.25 MHz
// - DIV_MODE = "5"
// - Risultato = 74.25 MHz
//
//============================================================================
