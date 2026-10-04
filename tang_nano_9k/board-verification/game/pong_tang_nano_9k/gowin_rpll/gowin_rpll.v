//============================================================================
// GOWIN rPLL - Phase-Locked Loop per generazione clock
//============================================================================
//
// CHE COS'È UN PLL?
// Il PLL (Phase-Locked Loop) è un circuito analogico/digitale che genera
// clock a frequenze diverse da quella di input. È fondamentale nelle FPGA
// perché spesso il clock esterno non ha la frequenza giusta per il progetto.
//
// COME FUNZIONA (semplificato):
// 1. Un oscillatore controllato in tensione (VCO) genera un clock ad alta freq.
// 2. Questo clock viene diviso e confrontato con il clock di input
// 3. Un circuito di feedback aggiusta il VCO finché le frequenze coincidono
// 4. Una volta "locked", il VCO genera un clock stabile e sincronizzato
//
// FORMULA PER CALCOLARE LA FREQUENZA:
//
//   f_VCO = f_CLKIN × (FBDIV_SEL + 1) × ODIV_SEL / (IDIV_SEL + 1)
//   f_CLKOUT = f_VCO / ODIV_SEL
//
// Quindi:
//   f_CLKOUT = f_CLKIN × (FBDIV_SEL + 1) / (IDIV_SEL + 1)
//
// LIMITI DEL VCO:
// Il VCO del GW1NR-9C deve operare tra 400 MHz e 1200 MHz.
// Se f_VCO è fuori da questo range, il PLL non funzionerà!
//
// NOSTRO CASO (640x480 @ 60Hz - VGA standard):
// - f_CLKIN = 27 MHz (oscillatore sulla board)
// - IDIV_SEL = 2 → divide per (2+1) = 3
// - FBDIV_SEL = 13 → moltiplica per (13+1) = 14
// - ODIV_SEL = 4
// - f_VCO = 27 × 14 × 4 / 3 = 504 MHz (OK, tra 400-1200 MHz)
// - f_CLKOUT = 504 / 4 = 126 MHz
//
// Questo è il clock 5× per TMDS. Diviso per 5 dà il pixel clock = 25.2 MHz.
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

module Gowin_rPLL (clkout, lock, clkin);

//============================================================================
// PORTE DEL MODULO
//============================================================================

// Clock di output generato dal PLL
// Questa è la frequenza principale che useremo (249.75 MHz)
output clkout;

// Segnale di "lock" - indica quando il PLL è stabile
// IMPORTANTE: Non usare clkout finché lock non è alto!
// Il PLL impiega alcuni microsecondi per stabilizzarsi all'accensione.
output lock;

// Clock di input (riferimento)
// Deve essere stabile e preciso - nel nostro caso 27 MHz dal cristallo
input clkin;

//============================================================================
// SEGNALI INTERNI
//============================================================================

// Uscite aggiuntive del PLL che non usiamo
// Il PLL può generare più clock con fasi o frequenze diverse
wire clkoutp_o;    // Clock con fase shiftata (non usato)
wire clkoutd_o;    // Clock diviso (non usato)
wire clkoutd3_o;   // Clock diviso per 3 (non usato)

// Segnali costanti per collegare ingressi non usati
// In Verilog, è buona pratica non lasciare ingressi "floating"
wire gw_vcc;       // Costante 1
wire gw_gnd;       // Costante 0

assign gw_vcc = 1'b1;   // 1'b1 = 1 bit, valore binario 1
assign gw_gnd = 1'b0;   // 1'b0 = 1 bit, valore binario 0

//============================================================================
// ISTANZA DEL PRIMITIVO rPLL
//============================================================================
// rPLL è una "primitiva" - un blocco hardware fisico dentro l'FPGA.
// Non è codice Verilog sintetizzabile, ma un componente reale del chip.
// Ogni famiglia di FPGA ha le sue primitive con nomi e parametri diversi.

rPLL rpll_inst (
    //----------------------------------------------------------------------
    // Uscite
    //----------------------------------------------------------------------
    .CLKOUT(clkout),        // Clock principale generato
    .LOCK(lock),            // Indica se il PLL è stabile
    .CLKOUTP(clkoutp_o),    // Clock con fase shiftata (non usato)
    .CLKOUTD(clkoutd_o),    // Clock diviso (non usato)
    .CLKOUTD3(clkoutd3_o),  // Clock diviso per 3 (non usato)

    //----------------------------------------------------------------------
    // Ingressi di controllo
    //----------------------------------------------------------------------
    .RESET(gw_gnd),         // Reset del PLL (0 = non resettato)
    .RESET_P(gw_gnd),       // Reset della fase (0 = non resettato)
    .CLKIN(clkin),          // Clock di input (27 MHz)
    .CLKFB(gw_gnd),         // Feedback esterno (0 = usa interno)

    //----------------------------------------------------------------------
    // Selezione dinamica dei divisori (non usata)
    //----------------------------------------------------------------------
    // Questi permettono di cambiare i divisori a runtime
    // Li colleghiamo tutti a 0 perché usiamo valori statici
    .FBDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),  // 6 bit
    .IDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),   // 6 bit
    .ODSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),   // 6 bit

    //----------------------------------------------------------------------
    // Controllo fase e duty cycle (non usato)
    //----------------------------------------------------------------------
    .PSDA({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),     // Phase shift
    .DUTYDA({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),   // Duty cycle
    .FDLY({gw_gnd,gw_gnd,gw_gnd,gw_gnd})      // Fine delay
);

//============================================================================
// PARAMETRI DEL PLL
//============================================================================
// I "defparam" impostano i parametri della primitiva.
// Questo è un modo obsoleto ma ancora supportato. Il modo moderno sarebbe
// usare la sintassi #(.PARAM(value)) nell'istanza.

// Frequenza del clock di input in MHz (come stringa)
defparam rpll_inst.FCLKIN = "27";

//--------------------------------------------------------------------------
// DIVISORE DI INPUT (IDIV)
//--------------------------------------------------------------------------
// Divide il clock di input prima del comparatore di fase
// f_PFD = f_CLKIN / (IDIV_SEL + 1)
//
// IDIV_SEL = 3 → divide per 4
// f_PFD = 27 / 4 = 6.75 MHz

defparam rpll_inst.DYN_IDIV_SEL = "false";  // Non usare selezione dinamica
defparam rpll_inst.IDIV_SEL = 2;            // Divide by 3

//--------------------------------------------------------------------------
// MOLTIPLICATORE DI FEEDBACK (FBDIV)
//--------------------------------------------------------------------------
// Determina di quanto il VCO deve essere più veloce del clock di input
// f_VCO = f_PFD × (FBDIV_SEL + 1) × ODIV_SEL
//
// FBDIV_SEL = 36 → moltiplica per 37
// f_VCO = 6.75 × 37 × 4 = 999 MHz

defparam rpll_inst.DYN_FBDIV_SEL = "false";  // Non usare selezione dinamica
defparam rpll_inst.FBDIV_SEL = 13;           // Multiply by 14

//--------------------------------------------------------------------------
// DIVISORE DI OUTPUT (ODIV)
//--------------------------------------------------------------------------
// Divide l'uscita del VCO per ottenere il clock finale
// f_CLKOUT = f_VCO / ODIV_SEL
//
// ODIV_SEL = 4
// f_CLKOUT = 999 / 4 = 249.75 MHz
//
// Valori possibili: 2, 4, 8, 16, 32, 48, 64, 80, 96, 112, 128

defparam rpll_inst.DYN_ODIV_SEL = "false";  // Non usare selezione dinamica
defparam rpll_inst.ODIV_SEL = 4;            // VCO=504MHz, Output=126MHz (5x ~25.2MHz)

//--------------------------------------------------------------------------
// PARAMETRI AVANZATI (valori di default)
//--------------------------------------------------------------------------
// Questi parametri controllano funzionalità avanzate che non usiamo

defparam rpll_inst.PSDA_SEL = "0000";        // Phase shift amount
defparam rpll_inst.DYN_DA_EN = "true";       // Enable dynamic adjustment
defparam rpll_inst.DUTYDA_SEL = "1000";      // Duty cycle (50%)
defparam rpll_inst.CLKOUT_FT_DIR = 1'b1;     // Fine tune direction
defparam rpll_inst.CLKOUTP_FT_DIR = 1'b1;    // Fine tune direction (phase)
defparam rpll_inst.CLKOUT_DLY_STEP = 0;      // Delay steps
defparam rpll_inst.CLKOUTP_DLY_STEP = 0;     // Delay steps (phase)
defparam rpll_inst.CLKFB_SEL = "internal";   // Usa feedback interno
defparam rpll_inst.CLKOUT_BYPASS = "false";  // Non bypassare PLL
defparam rpll_inst.CLKOUTP_BYPASS = "false"; // Non bypassare PLL (phase)
defparam rpll_inst.CLKOUTD_BYPASS = "false"; // Non bypassare divisore
defparam rpll_inst.DYN_SDIV_SEL = 2;         // Divisore secondario
defparam rpll_inst.CLKOUTD_SRC = "CLKOUT";   // Sorgente per CLKOUTD
defparam rpll_inst.CLKOUTD3_SRC = "CLKOUT";  // Sorgente per CLKOUTD3

// Dispositivo target - IMPORTANTE per la sintesi corretta
defparam rpll_inst.DEVICE = "GW1NR-9C";

endmodule //Gowin_rPLL

//============================================================================
// NOTE AGGIUNTIVE SUL PLL
//============================================================================
//
// COME CALCOLARE I PARAMETRI PER UNA NUOVA FREQUENZA:
//
// 1. Decidi la frequenza di output desiderata (es. 200 MHz)
// 2. Scegli ODIV_SEL (inizia con 4 o 8)
// 3. Calcola f_VCO = f_OUT × ODIV_SEL (deve essere 400-1200 MHz)
// 4. Scegli IDIV_SEL per avere f_PFD ragionevole (3-400 MHz)
// 5. Calcola FBDIV_SEL = f_VCO / (f_PFD × ODIV_SEL)
// 6. Verifica: f_OUT = 27 × (FBDIV+1) / (IDIV+1)
//
// ESEMPIO per 200 MHz:
// - ODIV = 4 → f_VCO = 800 MHz
// - IDIV = 2 (div 3) → f_PFD = 9 MHz
// - FBDIV = f_VCO / f_PFD / 1 - 1 = 800/9/1 - 1 ≈ 88... troppo alto!
// - Proviamo IDIV = 0 (div 1) → f_PFD = 27 MHz
// - FBDIV = 800 / 27 - 1 ≈ 29
// - Verifica: 27 × 30 / 1 = 810 MHz VCO, 810/4 = 202.5 MHz ✓
//
// TROUBLESHOOTING:
// - Se LOCK non va mai alto: f_VCO è fuori range (400-1200 MHz)
// - Se il clock è instabile: prova IDIV più basso per f_PFD più alta
// - Se hai jitter: usa CLKFB_SEL = "internal" (default)
//
//============================================================================
