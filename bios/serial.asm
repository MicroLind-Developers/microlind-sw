; Name: SER_INIT_6552
; Purpose: Initialize 65c52 serial controller
; Entry: None
; Exit: None
; Registers Used: A, X
; Example:
;       JSR SER_INIT_6552

    ;INCLUDE "system_defines.asm"

    ORG     $FF90                   ; Start address

; Define UART register offsets
; COM1 READ
UART_R_ISR1     EQU     $00             ; Interrupt Status Register COM1
UART_R_CSR1     EQU     $01             ; Command Register
UART_R_RDR1     EQU     $03             ; Recieve Data Register if read

; COM1 WRITE
UART_W_IER1     EQU     $00             ; Interrupt Enable Register COM1
UART_W_CR1      EQU     $01             ; Control Register ($00-$7F in data)
UART_W_FR1      EQU     $01             ; Format Register ($80-$FF in data)
UART_W_CDR1     EQU     $02             ; Compare Data Register (if bit 6 in CR1 is 0)
UART_W_ACR1     EQU     $02             ; Auxiliary Control Register (if bit 6 in CR1 is 1)
UART_W_TDR1     EQU     $03             ; Transmit Data Register if written to

; COM2 READ
UART_R_ISR2     EQU     $04             ; Interrupt Status Register COM2
UART_R_CSR2     EQU     $05             ; Command Register
UART_R_RDR2     EQU     $07             ; Recieve Data Register if read

; COM2 WRITE
UART_W_IER2     EQU     $04             ; Interrupt Enable Register COM2
UART_W_CR2      EQU     $05             ; Control Register ($00-$7F in data)
UART_W_FR2      EQU     $05             ; Format Register ($80-$FF in data)
UART_W_CDR2     EQU     $06             ; Compare Data Register (if bit 6 in CR2 is 0)
UART_W_ACR2     EQU     $06             ; Auxiliary Control Register (if bit 6 in CR2 is 1)
UART_W_TDR2     EQU     $07             ; Transmit Data Register if written to

; UART CONTROL REGISTER VALUE DEFINES
CR_SELECT       EQU     $00
CR_ACC_ACR      EQU     $40             ; bit 6 - 1
CR_ACC_CDR      EQU     $00             ; bit 6 - 0
CR_STOP_BITS    EQU     $20             ; bit 5
CR_ECHO         EQU     $10             ; bit 4
; bit 3-0 is bit rate selection:
CR_BIT_9600     EQU     $0C             ; 9600 baud
CR_BIT_19200    EQU     $0D             ; 19200 baud
CR_BIT_38400    EQU     $0E             ; 38400 baud

; Default configs: 38400-8N1, No echo and DTR & RTS high
CR_DEFAULT      EQU     $0E
FR_DEFAULT      EQU     $E3

; UART FORMAT REGISTER VALUE DEFINES
FR_SELECT       EQU     $80
FR_DB_5         EQU     $00
FR_DB_6         EQU     $20
FR_DB_7         EQU     $40
FR_DB_8         EQU     $60
FR_PAR_ODD      EQU     $00
FR_PAR_EVEN     EQU     $04
FR_PAR_MARK     EQU     $08
FR_PAR_SPACE    EQU     $18
FR_PAR_ENABLE   EQU     $04
FR_PAR_DISABLE  EQU     $00
FR_DTR_CTRL     EQU     $02
FR_RTS_CTRL     EQU     $01

; UART AUXILIARY CONTROL REGISTER VALUE DEFINES
ACR_TX_BRK      EQU     $02         ; Transmit breaks
ACR_PAR_MODE    EQU     $01         ; if 1: Send value of parity to ISR bit 2, 
                                    ; if 0: Send parity error status to ISR bit 2

;Name: SER_INIT
;Purpose:   Initialize 6552 DUART 
;Entry:     Nothing
;Exit       Nothing (yet)
;Registers used:
;           A, X
SER_INIT:
        LDX     #UART_BASE          ; Load UART base address into index register X

        ; Clear interrupt enable registers
        LDA     #$7F                ; Load A with zero (clearing ISR)
        STA     UART_W_IER1,X       ; Store A into UART base address + UART_ISR
        STA     UART_W_IER2,X       ; Store A into UART base address + UART_ISR
        
        ; Write control registers
        LDA     #CR_DEFAULT         ; Load control register defaults
        STA     UART_W_CR1,X        ; Store in control register 1
        STA     UART_W_CR2,X        ; Store in control register 2
        LDA     #FR_DEFAULT         ; Load format register defaults
        STA     UART_W_FR1,X        ; Store in format register 1
        STA     UART_W_FR2,X        ; Store in format register 2
        
        ; Read interupt status registers to clear
        LDA     UART_R_ISR1,X
        LDA     UART_R_ISR2,X

        ; Read control status registers to clear
        LDA     UART_R_CSR1,X
        LDA     UART_R_CSR2,X

        ; Read receiver data registers to clear
        LDA     UART_R_RDR1,X
        LDA     UART_R_RDR2,X

        RTS                         ; Return from subroutine

;Name: SER_INIT
;Purpose:   Initialize 6552 DUART 
;Entry:     A = Pointer to null terminated string 
;Exit       Nothing (yet)
;Registers used:
;           A, X

PRINT_S1:
	LDY     #UART_BASE
CHECK_READY:
        LDA 	#%00000010
        ANDA 	UART_R_ISR1,Y
        BEQ 	CHECK_READY

	LDA	,X+
	BEQ 	END_STRING
        STA     UART_W_TDR1,Y
	BRA 	CHECK_READY 	;next character

END_STRING:
	RTS			;Return from subroutine

IO_BASE     EQU     $F400
UART_BASE   EQU     IO_BASE + 0