; -----------------------------------------------------------------
; PROTECTED MODE HANDLER
; When the user need to do an i/o or memory operation, all those calls
; needs to go thru the pm-handler. What the pm-handler does is to 
; make the requested call, safely, from the kernel, and then return 
; to normal operation. Following is a simple process description:
;
; 1. The software sets up X register with the operation ID for what
;    it wants to do. For example: 0x1001 - Read Parallell port status
; 2. Sw calls the software interrupt, SWI
; 3. The PM circuit catches the interrupt and toggles Protected Mode on.
; 4. The SWI routing decodes what the software wants to do and
;    executes the request.
; 5. If required the SWI routine pushes response in to the Y register.
; 6. SWI routine makes a call to set the PM circuit to PM off. (just a write to $F402)
; 7. SWI returns from interrupt
; 8. Sw can evaluate return value and continue. 
; -----------------------------------------------------------------

