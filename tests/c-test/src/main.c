#include "registers.h"
#include "bios.h"


int main(void) {
    mmu_init();
    serial_init();
    serial_start();
    serial_print("Hello, World!\n");

    // Set the MMU driver
    char* mmu_driver = (char*)MMU_REG_0;
    mmu_driver[0] = 0x00;
    mmu_driver[1] = 0x01;
    mmu_driver[2] = 0x02;
    mmu_driver[3] = 0x03;

    // Copy the driver to the RAM
    char* from = (char*)0xF000;
    char* to = 0x0000;
    
    for(;;){
        *to++ = *from++;
        if(from >= (char*)0xFFF0) {
            break;
        }
    }
    return 0;
}

