#ifndef IO_H
#define IO_H

#define IO_BASE                     (0xF400)
#define STACK_START                 (0xDFFF)
#define STACK_SIZE                  (1024)

#define BIOS_RAM_START              (0xD800)

//-----------------------------------------------------------------
//Memory Mapper (MMU) 
// Register Map $F400 - $F403
//-----------------------------------------------------------------
#define MMU_BASE                    (IO_BASE + 0)

#define MMU_REG_0                   (MMU_BASE + 0)
#define MMU_REG_1                   (MMU_BASE + 1)
#define MMU_REG_2                   (MMU_BASE + 2)
#define MMU_REG_3                   (MMU_BASE + 3)

//-----------------------------------------------------------------
//IRQ Handler
//$F404
//-----------------------------------------------------------------
#define IRQ_BASE (IO_BASE + 4)

//-----------------------------------------------------------------
//Spare 1 
//$F405 - $F40F
//-----------------------------------------------------------------
#define SPARE_1_BASE (IO_BASE + 5)

//-----------------------------------------------------------------
// Expansion Port
// Register Map $F500 - $F7FF
// Memory Map   $D800 - $D81F
// Buffer       None
//-----------------------------------------------------------------
#define EXPANSION_PORT_BASE             (IO_BASE + 256)
#define EXPANSION_DRIVER_RAM_START      (BIOS_RAM_START)
#define EXPANSION_DRIVER_RAM_SIZE       (32)

//-----------------------------------------------------------------
// Serial (XR88C92)
// Register Map $F430 - $F43F 
// Memory Map   $D820 - $D83F
// Buffer       $D000 - $D3FF
//-----------------------------------------------------------------
#define SERIAL_BASE                     (IO_BASE + 48)
#define SERIAL_DRIVER_RAM_START         (EXPANSION_DRIVER_RAM_START + EXPANSION_DRIVER_RAM_SIZE)
#define SERIAL_DRIVER_RAM_SIZE          (32)
#define SERIAL_BUFFER_START 	        (0xD000)
#define SERIAL_BUFFER_SIZE 	            (1024)

// Port A
#define SERIAL_MRA                      (SERIAL_BASE + 0)   // Mode Register A 0 - 2
#define SERIAL_SRA                      (SERIAL_BASE + 1)   // Status Register A
#define SERIAL_RXA                      (SERIAL_BASE + 3)   // Receive Data Register A
#define SERIAL_TXA                      (SERIAL_BASE + 3)   // Transmit Data Register A
#define SERIAL_CRA                      (SERIAL_BASE + 2)   // Command Register A
#define SERIAL_CSRA                     (SERIAL_BASE + 1)   // Clock Select Register A

// Port B
#define SERIAL_MRB                      (SERIAL_BASE + 8)   // Mode Register B 0 - 2
#define SERIAL_SRB                      (SERIAL_BASE + 9)   // Status Register B
#define SERIAL_RXB                      (SERIAL_BASE + 11)  // Receive Data Register B
#define SERIAL_TXB                      (SERIAL_BASE + 11)  // Transmit Data Register B
#define SERIAL_CRB                      (SERIAL_BASE + 10)  // Command Register B
#define SERIAL_CSRB                     (SERIAL_BASE + 9)   // Clock Select Register B

// Common
#define SERIAL_ACR                      (SERIAL_BASE + 4)   // Auxilliary Control Register
#define SERIAL_ISR                      (SERIAL_BASE + 5)   // Interrupt Status Register   
#define SERIAL_IMR                      (SERIAL_BASE + 5)   // Interrupt Mask Register
#define SERIAL_IPCR                     (SERIAL_BASE + 4)   // Input Port Change Register 
#define SERIAL_OPCR                     (SERIAL_BASE + 13)  // Output Port Configuration Register
#define SERIAL_IPR                      (SERIAL_BASE + 13)  // Input Port Register (Bit 0-6)
#define SERIAL_SPCR                     (SERIAL_BASE + 15)  // Stop Counter/Timer Register
#define SERIAL_ROPR                     (SERIAL_BASE + 15)  // Reset Output Port Register
#define SERIAL_SOPR                     (SERIAL_BASE + 14)  // Set Output Port Register
#define SERIAL_STCR                     (SERIAL_BASE + 14)  // Start Counter/Timer Register
#define SERIAL_GPR                      (SERIAL_BASE + 12)  // General Purpose Register
#define SERIAL_CUR                      (SERIAL_BASE + 6)   // Counter/Timer Upper Register
#define SERIAL_CLR                      (SERIAL_BASE + 7)   // Counter/Timer Lower Register
#define SERIAL_CTPU                     (SERIAL_BASE + 6)   // Counter/Timer Preset Upper Register
#define SERIAL_CTPL                     (SERIAL_BASE + 7)   // Counter/Timer Preset Lower Register

//-----------------------------------------------------------------
// Compact Flash
// Register Map $F420 - $F42F
// Memory Map   $D840 - $D85F
// Buffer       $D400 - $D5FF
//-----------------------------------------------------------------
#define CF_BASE                         (IO_BASE + 24)
#define STORAGE_DRIVER_RAM_START        (SERIAL_DRIVER_RAM_START + SERIAL_DRIVER_RAM_SIZE)
#define STORAGE_DRIVER_RAM_SIZE         (32)
#define STORAGE_BUFFER_START 	        (0xD400)
#define STORAGE_BUFFER_SIZE 	        (512)

#define CF_DATA                         (CF_BASE + 0)   // Data register (read/write)
#define CF_ERROR                        (CF_BASE + 1)   // Error register (read only)
#define CF_FEATURES                     (CF_BASE + 1)   // Features register (write only)
#define CF_SECTOR_COUNT                 (CF_BASE + 2)
#define CF_LBA0                         (CF_BASE + 3)
#define CF_LBA1                         (CF_BASE + 4)
#define CF_LBA2                         (CF_BASE + 5)
#define CF_DRIVE_HEAD                   (CF_BASE + 6)
#define CF_STATUS                       (CF_BASE + 7)   // Status register (read)
#define CF_COMMAND                      (CF_BASE + 7)   // Command register (write)

//-----------------------------------------------------------------
// Parallel (VIA)
// Register Map $F420 - $F42F
// Memory Map   $D860 - $D87F
// Buffer       $D600 - $D67F
//-----------------------------------------------------------------
#define PARALLEL_BASE                   (IO_BASE + 32)
#define JOYSTICK_DRIVER_RAM_START       (STORAGE_DRIVER_RAM_START + STORAGE_DRIVER_RAM_SIZE)
#define JOYSTICK_DRIVER_RAM_SIZE        (32)
#define SPI_DRIVER_RAM_BUFFER_START     (JOYSTICK_DRIVER_RAM_START + JOYSTICK_DRIVER_RAM_SIZE)
#define SPI_DRIVER_RAM_SIZE             (32)

#define PARALLEL_ORB                    (PARALLEL_BASE + 0)
#define PARALLEL_IRB                    (PARALLEL_BASE + 0)
#define PARALLEL_ORA                    (PARALLEL_BASE + 1)
#define PARALLEL_IRA                    (PARALLEL_BASE + 1)
#define PARALLEL_DDRA                   (PARALLEL_BASE + 2)
#define PARALLEL_DDRB                   (PARALLEL_BASE + 3)
#define PARALLEL_T1CL                   (PARALLEL_BASE + 4)
#define PARALLEL_T1CH                   (PARALLEL_BASE + 5)
#define PARALLEL_T1LL                   (PARALLEL_BASE + 6)
#define PARALLEL_T1LH                   (PARALLEL_BASE + 7)
#define PARALLEL_T2CL                   (PARALLEL_BASE + 8)
#define PARALLEL_T2CH                   (PARALLEL_BASE + 9)
#define PARALLEL_SR                     (PARALLEL_BASE + 10)
#define PARALLEL_ACR                    (PARALLEL_BASE + 11)
#define PARALLEL_PCR                    (PARALLEL_BASE + 12)
#define PARALLEL_IFR                    (PARALLEL_BASE + 13)
#define PARALLEL_IER                    (PARALLEL_BASE + 14)

//-----------------------------------------------------------------
// Keyboard (PS/2)
// Register Map $F410 - $F417
// Memory Map   $D880 - $D89F : Keyboard 
//              $D8A0 - $D8BF : Mouse
// Buffer       $D600 - $D63F : Keyboard
//              $D680 - $D6BF : Mouse
//-----------------------------------------------------------------
#define PS2_BASE                        (IO_BASE + 16)
#define KEYBOARD_DRIVER_RAM_START       (SPI_DRIVER_RAM_BUFFER_START + SPI_DRIVER_RAM_SIZE)
#define KEYBOARD_DRIVER_RAM_SIZE        (32)
#define KEYBOARD_BUFFER_START           (0xD600)
#define KEYBOARD_BUFFER_SIZE            (64)

#define MOUSE_DRIVER_RAM_START          (KEYBOARD_DRIVER_RAM_START + KEYBOARD_DRIVER_RAM_SIZE)
#define MOUSE_DRIVER_RAM_SIZE           (32)
#define MOUSE_BUFFER_START 	            (0xD640)
#define MOUSE_BUFFER_SIZE 	            (64)

#define PS2_KBD                         (PS2_BASE + 0) // Keypress / Kbd command
#define PS2_MOUSE                       (PS2_BASE + 1) // Mouse

//-----------------------------------------------------------------
// Graphics
// Register Map $F440 - $F47F
// Memory Map   $D8A0 - $D8DF
// Buffer       $CC00 - $D000
//-----------------------------------------------------------------
#define GRAPHICS_BASE                   (IO_BASE + 64)

#define VIDEO_DRIVER_RAM_START          (MOUSE_DRIVER_RAM_START + MOUSE_DRIVER_RAM_SIZE)
#define VIDEO_DRIVER_RAM_SIZE           (64)
#define VIDEO_BUFFER_START 	            (0xCC00)
#define VIDEO_BUFFER_SIZE 	            (1024)

//-----------------------------------------------------------------
//Audio
// Register Map $F480 - $F4BF
// Memory Map   $D8E0 - $D8FF
// Buffer       $C800 - $CC00
//-----------------------------------------------------------------
#define AUDIO_BASE                      (IO_BASE + 128)
#define AUDIO_DRIVER_RAM_START          (VIDEO_DRIVER_RAM_START + VIDEO_DRIVER_RAM_SIZE)
#define AUDIO_DRIVER_RAM_SIZE           (32)
#define AUDIO_BUFFER_START 	            (0xC800)
#define AUDIO_BUFFER_SIZE 	            (1024)

//-----------------------------------------------------------------
//Spare 2
// Register Map $F4C0 - $F4FF
// Memory Map   None
// Buffer       None
//-----------------------------------------------------------------
#define SPARE_2_BASE                    (IO_BASE + 192)

#endif