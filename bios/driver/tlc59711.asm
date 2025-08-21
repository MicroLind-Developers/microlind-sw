; -----------------------------------------------------------------
; TLC59711 driver
; This driver is used to control the TLC59711 LED driver
; used for the led expansion board with 4 RGB LEDs 
; This driver is connected to the CB1 and CB2 pin of the 6522 parallel port
; and need the 6522 driver to be initialized and have the SPI output enabled
; The TLC59711 expects 224 bits of data per transfer, 
; 16 bits per color of 4 LEDs
; -----------------------------------------------------------------

; 16 bits per color of 4 LEDs
LED_DATA_BASE equ $CC00

LED_1_RED_DATA equ LED_DATA_BASE
LED_1_GREEN_DATA equ LED_DATA_BASE + 2
LED_1_BLUE_DATA equ LED_DATA_BASE + 4

LED_2_RED_DATA equ LED_DATA_BASE + 6
LED_2_GREEN_DATA equ LED_DATA_BASE + 8
LED_2_BLUE_DATA equ LED_DATA_BASE + 10

LED_3_RED_DATA equ LED_DATA_BASE + 12
LED_3_GREEN_DATA equ LED_DATA_BASE + 14
LED_3_BLUE_DATA equ LED_DATA_BASE + 16

LED_4_RED_DATA equ LED_DATA_BASE + 18
LED_4_GREEN_DATA equ LED_DATA_BASE + 20
LED_4_BLUE_DATA equ LED_DATA_BASE + 22

; -----------------------------------------------------------------
; INITIALIZE TLC59711
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
TLC59711_INIT:
        rts


; -----------------------------------------------------------------
; SET LED DATA
; input:            A = LED number (1-4)
;                   U = Blue data
;                   U -2 = Green data
;                   U -4 = Red data
; output:           None
; clobbers:         None
; -----------------------------------------------------------------
TLC59711_SET_LED_DATA:
    PSHS A,X       ; Save A,  X

    LSL A            ; A * 2
    TFR A,B          ; B = A * 2
    LSL A            ; A * 4
    ADDR B, A         ; A * 4 + B = A * 6

    LDX #LED_DATA_BASE
    ADDR A, X        ; X = X + A * 6

    LDB #6
_LED_DATA_COPY:
    PULU A           ; Pull byte from U stack
    STA ,X+          ; Store byte in X and increment X
    DECB
    BNE _LED_DATA_COPY

    PULS X,A,PC    ; Restore X, E, A and return

; -----------------------------------------------------------------
; SEND LED DATA
; input:            None
; output:           None
; clobbers:         None
; -----------------------------------------------------------------
TLC59711_SEND_LED_DATA:
    
    rts