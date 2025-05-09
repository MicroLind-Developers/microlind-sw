 org $F000

; This program tests the serial timer interrupt on the Microlind system.
; It sets up the timer to trigger an interrupt every 1/50 of a second and prints a message when 1 second has elapsed.

COUNTER EQU $00

_START:

    ldx #msg_test_hello
    jsr SERIAL_PRINT_A
    
    lda #$0E              ; Enable Serial IRQ on microlind
    jsr IRQ_SET_FILTER

    ; Enable serial timer interrupt
    lda #$07
    jsr SERIAL_SET_CT_MODE
    ldd #$1200  ; Set timer to a value that gives us 50 ticks per second      
    jsr SERIAL_SET_CT
    ldd #TIMER_IRQ_ROUTINE
    jsr SET_SERIAL_TIMER_IRQ_JUMP_VECTOR

    clr $00	; Clear the counter

    jsr SERIAL_ENABLE_CT_IRQ	; Enable the timer interrupt
    jsr SERIAL_START_CT	        ; Start the timer

_WAIT_LOOP:
    CWAI #$BF
    bra _WAIT_LOOP


TIMER_IRQ_ROUTINE:
    inc COUNTER		; Increment the counter
    lda COUNTER		; Load the counter value
    cmpa #$32		; Compare with 3 (3 seconds)
    beq _jobs_done	; If equal, branch to _jobs_done
    rts

_jobs_done: 
    ldx #msg_irq_handled
    jsr SERIAL_PRINT_A

    clr COUNTER		; Clear the counter
    rts

msg_test_hello: 
    fcc "Hello from the timer test program!"
    fcb 13,10,0
msg_irq_handled: 
    fcc "50 frames has passed!"
    fcb 13,10,0