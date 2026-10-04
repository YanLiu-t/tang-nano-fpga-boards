//============================================================================
// I2C Master per PCF8591
//============================================================================
//
// COSA FA QUESTO MODULO:
// Legge continuamente il valore analogico da un ADC PCF8591 collegato via I2C.
// Il valore letto (0-255) rappresenta la tensione sul pin ADC selezionato.
//
// COS'È L'I2C:
// I2C (Inter-Integrated Circuit) è un bus seriale a 2 fili:
// - SCL (Serial Clock): clock generato dal master
// - SDA (Serial Data): dati bidirezionali
//
// Caratteristiche I2C:
// - Multi-master, multi-slave (noi usiamo 1 master, 1 slave)
// - Ogni slave ha un indirizzo a 7 bit
// - Velocità standard: 100 kHz (noi), fast: 400 kHz, high-speed: 3.4 MHz
// - Open-drain: i dispositivi possono solo tirare la linea BASSA
//   (serve pull-up esterno per portarla alta)
//
// PROTOCOLLO I2C BASE:
// 1. START: SDA scende mentre SCL è alto
// 2. Byte di indirizzo: 7 bit indirizzo + 1 bit R/W
// 3. ACK: lo slave tira SDA basso per confermare
// 4. Byte dati (uno o più)
// 5. STOP: SDA sale mentre SCL è alto
//
// PCF8591:
// È un ADC/DAC a 8 bit della NXP. Ha:
// - 4 ingressi analogici (AIN0-AIN3)
// - 1 uscita analogica (AOUT)
// - Indirizzo base: 0x48 (modificabile con pin A0-A2)
//
//============================================================================

//----------------------------------------------------------------------------
// DICHIARAZIONE DEL MODULO
//----------------------------------------------------------------------------
// "module" è la parola chiave per definire un blocco hardware.
// È come una "classe" in OOP: definisce ingressi, uscite e comportamento.
// Quando lo istanzi in un altro modulo, crei una "copia" fisica del circuito.

module i2c_master (
    //------------------------------------------------------------------------
    // PORTE DI INPUT
    //------------------------------------------------------------------------
    // "input" = segnale che entra nel modulo (non possiamo modificarlo)
    // "wire" = tipo di segnale "combinatorio" (default per input)

    input wire clk,              // Clock di sistema (~50 MHz)
                                 // Tutti i flip-flop nel modulo sono sincronizzati
                                 // sul fronte di salita (posedge) di questo clock.
                                 // 50 MHz = 20 ns per ciclo

    input wire resetn,           // Reset attivo basso (la 'n' finale = active-low)
                                 // Quando resetn=0, il modulo si resetta
                                 // Quando resetn=1, funzionamento normale
                                 // Attivo-basso è comune perché i primi chip
                                 // avevano pin di reset open-drain

    //------------------------------------------------------------------------
    // CONFIGURAZIONE
    //------------------------------------------------------------------------
    input wire [1:0] channel,    // Canale ADC da leggere (0-3)
                                 // [1:0] significa "2 bit": bit 1 e bit 0
                                 // Può valere: 00=AIN0, 01=AIN1, 10=AIN2, 11=AIN3
                                 // Nel nostro progetto è fissato a 2'b10 (AIN2)

    //------------------------------------------------------------------------
    // BUS I2C
    //------------------------------------------------------------------------
    // "inout" = segnale bidirezionale (può essere input o output)
    // Necessario perché SDA è usato sia per trasmettere che per ricevere

    inout wire sda,              // I2C data line (bidirezionale)
                                 // Open-drain: può solo essere tirato basso o
                                 // lasciato flottante (il pull-up lo porta alto)

    // "output" = segnale che esce dal modulo
    output wire scl,             // I2C clock line
                                 // Generato sempre da noi (siamo il master)
                                 // ~100 kHz nel nostro caso

    //------------------------------------------------------------------------
    // PORTE DI OUTPUT
    //------------------------------------------------------------------------
    // "reg" = tipo di segnale che può essere assegnato in un blocco "always"
    // Non significa necessariamente un registro fisico, ma che il valore
    // viene "ricordato" tra un'assegnazione e l'altra.

    output reg [7:0] adc_value,  // Valore ADC letto (0-255)
                                 // [7:0] = 8 bit, può rappresentare 0-255
                                 // Viene aggiornato ogni ~1ms (tempo di una lettura I2C)

    output reg data_valid,       // Impulso alto per 1 ciclo quando adc_value è valido
                                 // Utile per sapere quando il dato è "fresco"

    // DEBUG: segnali per logic analyzer
    output wire debug_scl_enable,
    output wire [3:0] debug_state,
    output wire debug_sda_out,
    output wire debug_sda_oe,
    output wire [3:0] debug_bit_count
);

//============================================================================
// PARAMETRI
//============================================================================
// "parameter" definisce una costante che può essere modificata quando
// il modulo viene istanziato. È come un argomento di default in una funzione.
// Sintassi per override: i2c_master #(.CLK_DIV(500)) inst_name (...);

// Divisore per generare il clock I2C da quello di sistema
// Formula: f_SCL = f_CLK / (CLK_DIV * 2)
// Con CLK_DIV=250 e f_CLK=50MHz: f_SCL = 50M / 500 = 100 kHz
parameter CLK_DIV = 250;

// "localparam" è come parameter ma NON può essere modificato dall'esterno.
// Usalo per costanti interne che non devono mai cambiare.

// Indirizzo I2C del PCF8591
// 0x48 = 0100_1000 in binario = 72 in decimale
// I primi 4 bit (0100) sono fissi per il PCF8591
// Gli ultimi 3 bit (100) dipendono dai pin A2,A1,A0 (tutti a GND = 000...
// aspetta, 100? Questo potrebbe essere un errore, dovrebbe essere 0x48 = 0100_1000,
// ma in realtà l'indirizzo a 7 bit è 1001_000 = 0x48. Vediamo...)
// In realtà: 7'h48 = 1001000 in binario a 7 bit, che è corretto per PCF8591
// con A2=A1=A0=0
localparam PCF8591_ADDR = 7'h48;

//============================================================================
// GENERATORE CLOCK I2C
//============================================================================
// Questa sezione genera il segnale SCL (clock I2C) dividendo il clock di sistema.
// SCL deve essere ~100 kHz, molto più lento dei 50 MHz di sistema.

//----------------------------------------------------------------------------
// Dichiarazione dei registri per il generatore di clock
//----------------------------------------------------------------------------

// Contatore per dividere il clock
// [8:0] = 9 bit, può contare da 0 a 511
// Ci servono almeno 8 bit per contare fino a 250 (CLK_DIV)
reg [8:0] clk_count;

// Registro che tiene lo stato attuale di SCL (alto o basso)
// Cambia ogni volta che clk_count raggiunge CLK_DIV-1
reg scl_reg;

// NUOVO: Abilitazione del clock
// Quando scl_enable=0, il clock si ferma (SCL resta al valore attuale)
// Questo permette alla FSM di preparare i dati prima del prossimo fronte
reg scl_enable;

// Segnali combinatori che indicano i fronti di SCL
// "wire" perché sono calcolati continuamente, non memorizzati
wire scl_rising, scl_falling;

//----------------------------------------------------------------------------
// Processo per generare SCL
//----------------------------------------------------------------------------
// "always @(posedge clk or negedge resetn)" significa:
// "esegui questo blocco ogni volta che clk sale O resetn scende"
//
// Questa è la sintassi per un flip-flop con reset asincrono.
// - posedge clk: fronte di salita del clock (normale operazione)
// - negedge resetn: fronte di discesa del reset (attiva il reset)

always @(posedge clk or negedge resetn) begin
    // "begin...end" raggruppa più istruzioni (come { } in C)

    if (!resetn) begin
        // Reset asincrono: quando resetn=0, resetta immediatamente
        // "!" è il NOT logico, quindi !resetn è vero quando resetn=0
        clk_count <= 0;      // "<=" è assegnazione "non-blocking" (standard per always @posedge)
        scl_reg <= 1;        // SCL parte alto (idle state per I2C)
    end else if (scl_enable) begin
        // MODIFICATO: il clock gira SOLO se scl_enable=1
        // Operazione normale (resetn=1 e clock abilitato)

        // Controlla se il contatore ha raggiunto il limite
        if (clk_count == CLK_DIV - 1) begin
            clk_count <= 0;           // Resetta il contatore
            scl_reg <= ~scl_reg;      // Inverte SCL ("~" è il NOT bit a bit)
                                      // Questo crea un'onda quadra
        end else begin
            clk_count <= clk_count + 1;  // Incrementa il contatore
        end
    end
    // Se scl_enable=0, non facciamo nulla: SCL resta fermo al valore attuale
end

//----------------------------------------------------------------------------
// Rilevamento fronti di SCL
//----------------------------------------------------------------------------
// Questi segnali sono alti per UN SOLO ciclo di clock quando SCL cambia.
// Sono fondamentali per la macchina a stati: le transizioni I2C avvengono
// sui fronti di SCL.

// SCL rising edge: contatore al massimo E SCL attualmente basso
// (il prossimo ciclo SCL diventerà alto)
assign scl_rising = (clk_count == CLK_DIV - 1) && !scl_reg;

// SCL falling edge: contatore al massimo E SCL attualmente alto
// (il prossimo ciclo SCL diventerà basso)
assign scl_falling = (clk_count == CLK_DIV - 1) && scl_reg;

// "assign" crea una connessione permanente (logica combinatoria)
// Il lato sinistro è SEMPRE uguale al lato destro, istantaneamente.
// È diverso da "<=" che aggiorna solo sul fronte del clock.

//============================================================================
// CONTROLLO SDA (linea dati)
//============================================================================
// SDA è bidirezionale e open-drain. Dobbiamo gestire:
// 1. Quando TRASMETTIAMO: pilotiamo SDA basso o lo lasciamo flottare
// 2. Quando RICEVIAMO: lasciamo flottare e leggiamo il valore

//----------------------------------------------------------------------------
// Registri di controllo SDA
//----------------------------------------------------------------------------

reg sda_out;        // Valore che vogliamo trasmettere (0 o 1)
reg sda_oe;         // Output Enable: 1 = stiamo trasmettendo, 0 = stiamo ricevendo

//----------------------------------------------------------------------------
// Logica tri-state per SDA
//----------------------------------------------------------------------------
// Questa è la parte cruciale per l'open-drain!
//
// Open-drain significa:
// - Possiamo SOLO tirare la linea BASSA (collegandola a GND)
// - Per farla andare ALTA, la RILASCIAMO (alta impedenza) e il pull-up la tira su
//
// In Verilog, "1'bz" rappresenta l'alta impedenza (Z = tri-state)

assign sda = (sda_oe && !sda_out) ? 1'b0 : 1'bz;

// Spiegazione della logica:
// - Se sda_oe=1 (stiamo trasmettendo) E sda_out=0 (vogliamo trasmettere 0):
//   → SDA = 0 (tiriamo basso)
// - Altrimenti:
//   → SDA = Z (alta impedenza, lasciamo flottare)
//
// Nota: quando sda_out=1, NON forziamo SDA alto! Lo lasciamo flottare.
// Il pull-up esterno lo porterà a livello alto.
// Questo è essenziale per permettere allo slave di fare ACK (tirare basso).

//----------------------------------------------------------------------------
// Lettura di SDA
//----------------------------------------------------------------------------
// Quando riceviamo dati o ACK, leggiamo il valore attuale di SDA

wire sda_in = sda;  // Semplice alias per chiarezza
                    // sda_in riflette sempre lo stato elettrico della linea

//============================================================================
// MACCHINA A STATI (FSM - Finite State Machine)
//============================================================================
// La FSM è il "cervello" del modulo. Controlla la sequenza di operazioni I2C.
//
// COS'È UNA FSM:
// È un circuito che può essere in uno di N "stati" discreti.
// Ad ogni ciclo di clock, in base allo stato attuale e agli input,
// decide: 1) cosa fare (output), 2) in quale stato andare dopo.
//
// Esempio semplicissimo - semaforo:
// Stati: ROSSO, GIALLO, VERDE
// Transizioni: ROSSO→VERDE→GIALLO→ROSSO (con timer)

//----------------------------------------------------------------------------
// Definizione degli stati
//----------------------------------------------------------------------------
// "localparam" per dare nomi leggibili ai numeri degli stati.
// Senza questi, il codice sarebbe pieno di numeri magici illeggibili.

localparam  S_IDLE          = 0,   // Attesa iniziale
            S_START         = 1,   // Genera condizione di START
            S_ADDR_W        = 2,   // Invia indirizzo + bit Write
            S_ACK1          = 3,   // Ricevi ACK dopo indirizzo
            S_CONTROL       = 4,   // Invia control byte (selezione canale)
            S_ACK2          = 5,   // Ricevi ACK dopo control byte
            S_RESTART       = 6,   // Genera REPEATED START
            S_ADDR_R        = 7,   // Invia indirizzo + bit Read
            S_ACK3          = 8,   // Ricevi ACK dopo indirizzo read
            S_READ_DUMMY    = 9,   // Leggi byte dummy (da scartare)
            S_ACK4          = 10,  // Invia ACK dopo dummy
            S_READ_DATA     = 11,  // Leggi byte dati reale
            S_NACK          = 12,  // Invia NACK (fine lettura)
            S_STOP          = 13,  // Genera condizione di STOP
            S_WAIT          = 14;  // Pausa prima di ricominciare

//----------------------------------------------------------------------------
// Registri della FSM
//----------------------------------------------------------------------------

reg [3:0] state;        // Stato attuale (4 bit per 15 stati)
reg [3:0] bit_count;    // Contatore bit trasmessi/ricevuti (0-8)
reg [7:0] shift_reg;    // Registro a scorrimento per TX/RX seriale
reg [7:0] read_data;    // Buffer per i dati ricevuti
reg [15:0] wait_count;  // Contatore per le pause
reg [7:0] setup_count;  // Contatore per timing START e setup

//----------------------------------------------------------------------------
// Control byte per il PCF8591
//----------------------------------------------------------------------------
// Formato: [0][AOE][AIP1][AIP0][0][AINC][CH1][CH0]
//
// Bit 7: 0 (fisso)
// Bit 6: AOE = Analog Output Enable (0 = disabilitato)
// Bit 5-4: AIP = Analog Input Programming (00 = 4 single-ended inputs)
// Bit 3: 0 (fisso)
// Bit 2: AINC = Auto-increment (0 = disabilitato)
// Bit 1-0: CH = Channel select (00=AIN0, 01=AIN1, 10=AIN2, 11=AIN3)
//
// Per leggere AIN2: control_byte = 0000_0010 = 0x02

wire [7:0] control_byte = {4'b0000, 2'b00, channel};
// { } è la concatenazione: unisce i bit in un unico vettore
// 4'b0000 = 4 bit a zero
// 2'b00 = 2 bit a zero
// channel = 2 bit dal parametro di input
// Risultato: 8 bit totali

//============================================================================
// PROCESSO PRINCIPALE DELLA FSM
//============================================================================
// Questo blocco always contiene TUTTA la logica della macchina a stati.
// È un blocco sequenziale (sincronizzato sul clock) con reset asincrono.

always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        //--------------------------------------------------------------------
        // RESET: inizializza tutti i registri
        //--------------------------------------------------------------------
        state <= S_IDLE;
        bit_count <= 0;
        shift_reg <= 0;
        read_data <= 0;
        sda_out <= 1;       // SDA alto (idle)
        sda_oe <= 0;        // Non stiamo trasmettendo
        adc_value <= 0;
        data_valid <= 0;
        wait_count <= 0;
        setup_count <= 0;   // NUOVO
        scl_enable <= 1;    // NUOVO: clock abilitato di default
    end else begin
        //--------------------------------------------------------------------
        // OPERAZIONE NORMALE
        //--------------------------------------------------------------------

        // Default: data_valid è normalmente basso
        // Diventa alto solo per 1 ciclo quando leggiamo un dato
        data_valid <= 0;

        // "case" è come "switch" in C: seleziona in base al valore di state
        case (state)

            //================================================================
            // S_IDLE: Stato di attesa iniziale
            //================================================================
            // Aspetta un po' prima di iniziare la comunicazione.
            // Questo dà tempo al sistema di stabilizzarsi dopo il reset.

            S_IDLE: begin
                sda_oe <= 0;        // Non trasmettiamo
                sda_out <= 1;       // SDA alto (idle)

                // Aspetta che wait_count raggiunga 0xFFFF (65535 cicli)
                // A 50 MHz: 65535 * 20ns = 1.3 ms
                if (wait_count == 16'hFFFF) begin
                    wait_count <= 0;
                    state <= S_START;   // Vai a generare lo START
                end else begin
                    wait_count <= wait_count + 1;
                end
            end

            //================================================================
            // S_START: Genera condizione di START
            //================================================================
            // START I2C: SDA scende da alto a basso MENTRE SCL è alto
            //
            // Timing:
            //        ____
            // SCL: _|    |____
            //      ____
            // SDA:     |______
            //          ^
            //          START

            S_START: begin
                // Genera START con timing corretto secondo specifiche I2C
                //
                // Requisiti I2C per START:
                // - tSU;STA (setup time): min 4.7µs in standard mode
                // - tHD;STA (hold time): min 4.0µs in standard mode
                //
                // Implementazione con setup_count:
                // - Fase 0: SDA alto, aspetta scl_rising
                // - Fasi 1-49: setup time (~1µs a 50MHz) - SDA alto, SCL alto
                // - Fase 50: tira SDA basso → START!
                // - Fase 51+: aspetta scl_falling per hold time (~4µs)
                //
                // Il setup time garantisce che SDA sia stabile alto prima di scendere.
                // Il hold time (dal falling di SDA al falling di SCL) è ~4µs.

                sda_oe <= 1;

                if (setup_count == 0) begin
                    // Fase 0: SDA alto, aspetta rising edge di SCL
                    sda_out <= 1;
                    if (scl_rising) begin
                        setup_count <= 1;
                    end
                end else if (setup_count < 50) begin
                    // Fasi 1-49: setup time (~1µs a 50MHz)
                    // SDA resta alto mentre SCL è alto
                    setup_count <= setup_count + 1;
                end else if (setup_count == 50) begin
                    // Fase 50: tira SDA basso → condizione di START!
                    // SDA scende mentre SCL è ancora alto
                    sda_out <= 0;
                    setup_count <= 51;
                end else begin
                    // Fase 51+: aspetta falling edge per completare hold time
                    // Hold time = tempo da SDA falling a SCL falling ≈ 4µs
                    if (scl_falling) begin
                        // START completato, prepara primo bit dell'indirizzo
                        // PCF8591_ADDR = 7'h48 = 1001000
                        // Byte completo: {1001000, 0} = 0x90 (write)
                        sda_out <= PCF8591_ADDR[6];  // bit 6 dell'indirizzo (=0)
                        shift_reg <= {PCF8591_ADDR[5:0], 1'b0, 1'b0};  // bits 5-0 + W + padding
                        bit_count <= 0;
                        setup_count <= 0;
                        state <= S_ADDR_W;
                    end
                end
            end

            //================================================================
            // S_ADDR_W: Invia byte indirizzo + bit Write
            //================================================================
            // Trasmette 8 bit serialmente, MSB first (bit più significativo prima)
            //
            // Timing I2C per trasmissione:
            // - Cambia SDA quando SCL è basso
            // - Lo slave campiona SDA quando SCL è alto
            //
            //        ____      ____
            // SCL: _|    |____|    |____
            //      ___________
            // SDA: _____X_____X_____
            //           ^     ^
            //         setup  sample

            S_ADDR_W: begin
                // Entra con sda_out = bit 7, bit_count = 0
                // 8 falling edges totali: 7 per settare bits 6-0, 1 per uscire
                if (scl_falling) begin
                    if (bit_count == 7) begin
                        // Dopo il falling del bit 0, rilascia SDA per ACK
                        sda_oe <= 0;
                        state <= S_ACK1;
                    end else begin
                        // Prepara il prossimo bit
                        sda_out <= shift_reg[7];
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        bit_count <= bit_count + 1;
                    end
                end
            end

            //================================================================
            // S_ACK1: Ricevi ACK dopo indirizzo
            //================================================================
            // Dopo ogni byte, lo slave deve mandare un ACK tirando SDA basso.
            // Se SDA resta alto, è un NACK (errore).
            //
            // FIX SEMPLICE: impostiamo sda_out con il primo bit del control byte
            // NELLO STESSO MOMENTO in cui carichiamo shift_reg.
            // Così quando SCL sale, SDA ha già il valore corretto.

            S_ACK1: begin
                // 1 solo pulse: entra con sda_oe = 0 (slave manda ACK)
                // Esce dopo il falling, preparando bit 7 del control byte
                if (scl_falling) begin
                    sda_oe <= 1;
                    sda_out <= control_byte[7];  // bit 7 = 0
                    shift_reg <= {control_byte[6:0], 1'b0};
                    bit_count <= 0;
                    state <= S_CONTROL;
                end
            end

            //================================================================
            // S_CONTROL: Invia control byte (selezione canale ADC)
            //================================================================
            // Stesso meccanismo di S_ADDR_W

            S_CONTROL: begin
                // Stesso pattern di S_ADDR_W
                if (scl_falling) begin
                    if (bit_count == 7) begin
                        sda_oe <= 0;  // Rilascia per ACK
                        state <= S_ACK2;
                    end else begin
                        sda_out <= shift_reg[7];
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        bit_count <= bit_count + 1;
                    end
                end
            end

            //================================================================
            // S_ACK2: Ricevi ACK dopo control byte
            //================================================================

            S_ACK2: begin
                // 1 pulse per ACK, poi prepara per RESTART
                if (scl_falling) begin
                    sda_oe <= 1;
                    sda_out <= 1;   // SDA alto per preparare RESTART
                    state <= S_RESTART;
                end
            end

            //================================================================
            // S_RESTART: Genera REPEATED START
            //================================================================
            // Il REPEATED START permette di cambiare direzione (da Write a Read)
            // senza rilasciare il bus (senza STOP).
            //
            // Sequenza:
            // 1. SDA alto mentre SCL è basso
            // 2. SCL sale
            // 3. SDA scende mentre SCL è alto → RESTART!

            S_RESTART: begin
                // Genera REPEATED START con timing identico a START
                //
                // Il REPEATED START ha gli stessi requisiti temporali dello START:
                // - tSU;STA (setup time): min 4.7µs
                // - tHD;STA (hold time): min 4.0µs
                //
                // Implementazione identica a S_START:
                // - Fase 0: SDA alto, aspetta scl_rising
                // - Fasi 1-49: setup time (~1µs) - SDA alto, SCL alto
                // - Fase 50: tira SDA basso → RESTART!
                // - Fase 51+: aspetta scl_falling per hold time (~4µs)

                sda_oe <= 1;

                if (setup_count == 0) begin
                    // Fase 0: SDA alto, aspetta rising edge di SCL
                    sda_out <= 1;
                    if (scl_rising) begin
                        setup_count <= 1;
                    end
                end else if (setup_count < 50) begin
                    // Fasi 1-49: setup time (~1µs a 50MHz)
                    setup_count <= setup_count + 1;
                end else if (setup_count == 50) begin
                    // Fase 50: tira SDA basso → condizione di RESTART!
                    sda_out <= 0;
                    setup_count <= 51;
                end else begin
                    // Fase 51+: aspetta falling edge per completare hold time
                    if (scl_falling) begin
                        // RESTART completato, prepara primo bit per lettura
                        // Byte completo: {1001000, 1} = 0x91 (read)
                        sda_out <= PCF8591_ADDR[6];  // bit 6 dell'indirizzo (=0)
                        shift_reg <= {PCF8591_ADDR[5:0], 1'b1, 1'b0};  // bits 5-0 + R + padding
                        bit_count <= 0;
                        setup_count <= 0;
                        state <= S_ADDR_R;
                    end
                end
            end

            //================================================================
            // S_ADDR_R: Invia byte indirizzo + bit Read
            //================================================================
            // Identico a S_ADDR_W ma con R/W=1 (Read)

            S_ADDR_R: begin
                // Stesso pattern di S_ADDR_W
                if (scl_falling) begin
                    if (bit_count == 7) begin
                        sda_oe <= 0;  // Rilascia per ACK
                        state <= S_ACK3;
                    end else begin
                        sda_out <= shift_reg[7];
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        bit_count <= bit_count + 1;
                    end
                end
            end

            //================================================================
            // S_ACK3: Ricevi ACK dopo indirizzo read
            //================================================================

            S_ACK3: begin
                // 1 pulse per ACK, poi inizia lettura
                if (scl_falling) begin
                    bit_count <= 0;
                    shift_reg <= 0;
                    state <= S_READ_DUMMY;
                end
            end

            //================================================================
            // S_READ_DUMMY: Leggi primo byte (da scartare)
            //================================================================
            // ATTENZIONE: Il PCF8591 ha una peculiarità!
            // Il primo byte che manda dopo un cambio di canale è la lettura
            // PRECEDENTE, non quella nuova. Quindi dobbiamo leggerlo e scartarlo.
            //
            // Ricezione seriale:
            // - Leggiamo SDA quando SCL è alto
            // - Shiftiamo il bit nel registro

            S_READ_DUMMY: begin
                if (scl_rising) begin
                    // Campiona il bit e shiftalo nel registro
                    shift_reg <= {shift_reg[6:0], sda_in};
                    // Esempio: shift_reg=8'b10110100, sda_in=1
                    // → shift_reg=8'b01101001
                    bit_count <= bit_count + 1;
                end
                if (scl_falling && bit_count == 8) begin
                    // Byte completo ricevuto, manda ACK
                    sda_oe <= 1;
                    sda_out <= 0;  // ACK = SDA basso
                    state <= S_ACK4;
                end
            end

            //================================================================
            // S_ACK4: Invia ACK e prepara lettura dato reale
            //================================================================

            S_ACK4: begin
                if (scl_falling) begin
                    sda_oe <= 0;        // Rilascia SDA per ricevere
                    bit_count <= 0;
                    state <= S_READ_DATA;
                end
            end

            //================================================================
            // S_READ_DATA: Leggi il byte con il valore ADC reale
            //================================================================
            // Questo è il dato che ci interessa!

            S_READ_DATA: begin
                if (scl_rising) begin
                    read_data <= {read_data[6:0], sda_in};
                    bit_count <= bit_count + 1;
                end
                if (scl_falling && bit_count == 8) begin
                    // Byte completo!
                    sda_oe <= 1;
                    sda_out <= 1;  // NACK = SDA alto (indica "ultimo byte")

                    // Salva il valore letto
                    // Usiamo sda_in direttamente per l'ultimo bit perché
                    // read_data non è ancora stato aggiornato in questo ciclo
                    adc_value <= {read_data[6:0], sda_in};
                    data_valid <= 1;  // Segnala che il dato è valido

                    state <= S_NACK;
                end
            end

            //================================================================
            // S_NACK: Stato dopo aver inviato NACK
            //================================================================
            // Il NACK dice allo slave "non mandare altri byte"

            S_NACK: begin
                if (scl_falling) begin
                    sda_out <= 0;  // Prepara SDA basso per lo STOP
                    state <= S_STOP;
                end
            end

            //================================================================
            // S_STOP: Genera condizione di STOP
            //================================================================
            // STOP I2C: SDA sale da basso a alto MENTRE SCL è alto
            //
            // Timing:
            //        ____
            // SCL: _|    |____
            //           ______
            // SDA: ____|
            //          ^
            //          STOP

            S_STOP: begin
                if (scl_rising) begin
                    sda_out <= 1;  // SDA sale mentre SCL è alto → STOP!
                end
                if (scl_falling) begin
                    sda_oe <= 0;   // Rilascia il bus
                    state <= S_WAIT;
                end
            end

            //================================================================
            // S_WAIT: Pausa tra letture successive
            //================================================================
            // Aspetta un po' prima di ricominciare.
            // Non è strettamente necessario, ma dà "respiro" al bus.

            S_WAIT: begin
                // 0x0FFF = 4095 cicli = ~82 µs a 50 MHz
                if (wait_count == 16'h0FFF) begin
                    wait_count <= 0;
                    state <= S_START;  // Ricomincia il ciclo
                end else begin
                    wait_count <= wait_count + 1;
                end
            end

        endcase  // Fine del case(state)
    end  // Fine del else (non reset)
end  // Fine del always

//============================================================================
// OUTPUT SCL
//============================================================================
// SCL è sempre pilotato da noi (siamo il master).
// Lo colleghiamo direttamente al registro scl_reg.
//
// Nota: in un sistema multi-master, anche SCL dovrebbe essere open-drain
// per permettere il clock stretching. Ma con un solo master, push-pull va bene.

assign scl = scl_reg;

// DEBUG: porta fuori segnali per logic analyzer
assign debug_scl_enable = scl_enable;
assign debug_state = state;
assign debug_sda_out = sda_out;
assign debug_sda_oe = sda_oe;
assign debug_bit_count = bit_count;

endmodule

//============================================================================
// RIEPILOGO DELLA SEQUENZA I2C COMPLETA
//============================================================================
//
// La sequenza per leggere un canale ADC dal PCF8591 è:
//
// 1. START
// 2. [Slave Addr 0x48 + W] → ACK
// 3. [Control Byte 0x02]   → ACK
// 4. RESTART
// 5. [Slave Addr 0x48 + R] → ACK
// 6. ← [Dummy Byte]        → ACK (mandiamo noi)
// 7. ← [ADC Value]         → NACK (ultimo byte)
// 8. STOP
//
// Sul bus I2C si vede:
//
// SDA: [S][1001000][0][A][00000010][A][S][1001001][A][xxxxxxxx][A][VVVVVVVV][N][P]
// SCL:    [______8_____] [____8____]   [______8_____] [___8____]  [___8____]
//
// Legenda:
// [S] = START
// [A] = ACK (dallo slave)
// [N] = NACK (da noi)
// [P] = STOP
// [V] = bit del valore ADC
//
//============================================================================

//============================================================================
// FIX IMPLEMENTATI: TIMING START/RESTART E PREPARAZIONE BIT
//============================================================================
//
// Durante il debug sono stati identificati e risolti diversi problemi:
//
// PROBLEMA 1: NAK sull'indirizzo (0x90 + NAK)
// -------------------------------------------
// CAUSA: La condizione di START non rispettava i requisiti temporali I2C.
// SDA scendeva quasi simultaneamente al rising edge di SCL (~20ns di ritardo),
// mentre lo standard I2C richiede:
// - tSU;STA (setup time) ≥ 4.7µs: SDA deve essere stabile alto
// - tHD;STA (hold time) ≥ 4.0µs: SDA deve restare basso dopo lo START
//
// SOLUZIONE: Aggiunto contatore setup_count per garantire il timing:
// - 50 cicli di setup (~1µs) dopo scl_rising prima di tirare SDA basso
// - Attesa di scl_falling per hold time (~4µs)
//
// PROBLEMA 2: setup_count overflow
// ---------------------------------
// CAUSA: setup_count era dichiarato a 4 bit (max 15) ma doveva contare fino a 50+.
// SOLUZIONE: Cambiato da reg [3:0] a reg [7:0].
//
// PROBLEMA 3: Indirizzo di lettura errato (0x48 invece di 0x91)
// -------------------------------------------------------------
// CAUSA: Stesso problema di timing in S_RESTART - nessun setup time.
// SOLUZIONE: Applicato lo stesso pattern di timing di S_START.
//
// PROBLEMA 4: Control byte errato (0x80 invece di 0x02)
// -----------------------------------------------------
// CAUSA: Il primo bit non era pronto quando lo slave lo campionava.
// sda_out veniva impostato solo al primo scl_falling DENTRO lo stato
// di trasmissione, ma lo slave campiona al scl_rising che avviene PRIMA.
//
// SOLUZIONE: Impostare sda_out con il primo bit GIÀ NELLO STATO PRECEDENTE.
// In S_ACK1, S_START, S_RESTART prepariamo il primo bit prima della transizione.
//
// ARCHITETTURA DELLA FSM:
// -----------------------
// Ogni stato di trasmissione (S_ADDR_W, S_CONTROL, S_ADDR_R):
// - Entra con sda_out già impostato al bit 7 (MSB)
// - shift_reg contiene i bit rimanenti (6-0) già shiftati
// - bit_count parte da 0
// - Ad ogni scl_falling: se bit_count < 7, carica il prossimo bit
// - Quando bit_count == 7, passa allo stato ACK
//
// Ogni stato ACK:
// - 1 solo pulse di clock
// - Prepara il primo bit dello stato successivo prima di transitare
//
//============================================================================
