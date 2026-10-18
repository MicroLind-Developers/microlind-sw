; Stage-3 hardware backend; do not include device addresses in syscall ABI.
MMU0        equ $F400
MMU1        equ $F401
MMU2        equ $F402
MMU3        equ $F403
IRQ_CONTROL equ $F404
GATE        equ $F405
GATE_BIT    equ $80
UART        equ $F430
UART_MRA    equ UART
UART_SRA    equ UART+1
UART_CRA    equ UART+2
UART_TXA    equ UART+3
UART_ACR    equ UART+4
UART_ISR    equ UART+5
UART_IMR    equ UART+5
UART_CTPU   equ UART+6
UART_CTPL   equ UART+7
UART_START  equ UART+14
UART_STOP   equ UART+15
UART_OPCR   equ UART+13
UART_LED_SET equ UART+14          ; writes: SOPR, independent of timer read commands
UART_LED_RESET equ UART+15        ; writes: ROPR
POWER_LED_ALL equ $70
POWER_LED_GREEN equ $20
POWER_LED_RED equ $10
UART_POLL_LIMIT equ 1024
