// Target-contract tests against the actual assembled ROM/core, no host model.
#include "microlind/app/hardware_config.hpp"
#include "microlind/app/image_loader.hpp"
#include "microlind/app/sim_builder.hpp"
#include "microlind/devices/serial.hpp"
#include "target_symbols.hpp"
#include <array>
#include <iostream>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <string>

using namespace microlind;
using namespace target;
void require(bool ok, const std::string& why) { if (!ok) throw std::runtime_error(why); }
struct Machine {
    devices::XR88C92* uart{};
    std::string serial;
    Simulator sim;
    bool micro;
    Machine(const cli::LoadedImage& image, const cli::HardwareConfig& config, bool cycles)
        : sim(cli::build_sim(CpuMode::HD6309, &image, &config, &uart,
              [this](uint8_t byte) { require(serial.size()<4096,"unbounded serial"); serial += char(byte); })), micro(cycles) {
        sim.bus().set_access_logging(false);
        sim.bus().set_detailed_bus_phases(false);
        sim.reset_from_vector();
    }
    void step() {
        if (micro) { do { sim.tick_microcycle(); } while (sim.has_pending_microcycles()); }
        else sim.tick();
    }
    template<class Predicate> void until(Predicate predicate, const std::string& why, unsigned limit=200000) {
        for (unsigned i=0;i<limit;++i) {
            if (predicate()) return;
            step();
        }
        throw std::runtime_error(why+" PC="+std::to_string(sim.cpu().regs().pc)+
            " phase="+std::to_string(sim.bus().peek8(TEST_STEP))+
            " panic="+std::to_string(sim.bus().peek8(PANIC_REASON)));
    }
    void boot() {
        until([&]{return sim.bus().peek8(TEST_RESULT)==0xA5 && sim.cpu().regs().pc==app_done;},"assembly selftest failed");
        require(serial=="MLOS S00-S02 PASS\r\n","serial pass marker");
        require(!sim.bus().privileged(),"application must be locked");
    }
    uint16_t call(uint8_t number, uint16_t params=0x100) {
        auto& r=sim.cpu().regs();
        sim.bus().write8(0x2000,0x3F); sim.bus().write8(0x2001,0x12);
        r.pc=0x2000; r.a=number; r.b=0x5A; r.x=params;
        r.s=APP_STACK; r.y=0x1357; r.u=0x2468; r.v=0xABCD;
        r.e=0x67; r.f=0x89; r.dp=0x12; r.cc=0x6E; // F masked, IRQ unmasked.
        until([&]{return r.pc==0x2001 && !sim.has_pending_microcycles();},"syscall did not return",20000);
        require(r.x==params && r.y==0x1357 && r.u==0x2468 && r.v==0xABCD,"registers X/Y/U/V");
        require(r.e==0x67 && r.f==0x89 && r.dp==0x12,"native E/F/DP");
        require((r.cc & 0xFE)==0xEE,"saved CC effects");
        require(r.s==APP_STACK,"application stack balance");
        require(sim.bus().peek8(MMU0)==APP_FRAME && sim.bus().peek8(MMU3)==COMMON_FRAME,"fixed maps");
        require(sim.bus().peek8(ENTRY_DEPTH)==0 && !sim.bus().privileged(),"entry depth/outer relock");
        return uint16_t((r.a<<8)|r.b);
    }
    void word(uint16_t addr,uint16_t value) { sim.bus().write8(addr,uint8_t(value>>8));sim.bus().write8(addr+1,uint8_t(value)); }
    bool failed() { return (sim.cpu().regs().cc & CC_C)!=0; }
};

void boundaries(Machine& m) {
    for(unsigned a=KERNEL_CANARY+2;a<KERNEL_STACK;++a)m.sim.bus().write8(a,0xCD);
    for(unsigned a=APP_STACK-1024;a<APP_STACK;++a)m.sim.bus().write8(a,0xCD);
    auto cycles=m.sim.clock().total_cycles();
    require(m.call(SYS_PROBE)==ABI_VERSION && !m.failed(),"probe");
    std::cout<<"probe syscall cycles="<<(m.sim.clock().total_cycles()-cycles)<<'\n';
    require(m.call(255)==uint16_t(SYS_ENOSYS) && m.failed(),"unknown syscall");
    cycles=m.sim.clock().total_cycles();
    require(m.call(SYS_ENTRY_TEST)==0x6309 && !m.failed(),"nested privileged call");
    std::cout<<"nested syscall cycles="<<(m.sim.clock().total_cycles()-cycles)<<'\n';
    uint16_t token=m.call(SYS_BANK_ALLOC); require(!m.failed(),"bank admission");
    m.word(0x100,token); m.sim.bus().write8(0x102,1);
    require(m.call(SYS_BANK_MAP)==0 && !m.failed(),"map window1");
    for (uint16_t length : {0,1,2,127,128,255,256}) {
        for (uint16_t source : {0x0000,0x3FFE,0x3FFF,0x4000,0x7FFF,0x8000,0xBFFF,0xC000,0xFFFF}) {
            // Source fill in live windows; no source overlaps the parameter block.
            for (unsigned i=0;i<length;++i) {
                if (unsigned(source)+i<0x8000) m.sim.bus().write8(uint16_t(source+i),uint8_t(i^0x96));
                m.sim.bus().write8(uint16_t(0x2100+i),0xA5);
            }
            m.word(0x100,source);m.word(0x102,0x2100);m.word(0x104,length);
            const bool valid=length==0 || unsigned(source)+length<=0x8000;
            const auto result=m.call(SYS_COPY);
            require(m.failed()!=valid,"copy boundary carry");
            require(result==(valid?length:uint16_t(SYS_EFAULT)),"copy boundary result");
            for (unsigned i=0;i<length;++i) require(m.sim.bus().peek8(uint16_t(0x2100+i))==(valid?uint8_t(i^0x96):0xA5),"copy atomicity/data");
        }
    }
    // All destination windows/range wrap, using a source containing known bytes.
    for (uint16_t dest : {0x3FFE,0x7FFE,0xBFFE,0xFFFE}) {
        for (unsigned i=0;i<4;++i) m.sim.bus().write8(0x2100+i,0x60+i);
        m.word(0x100,0x2100);m.word(0x102,dest);m.word(0x104,4);
        const auto before=m.sim.bus().peek8(dest); const bool valid=dest==0x3FFE;
        m.call(SYS_COPY);require(m.failed()!=valid,"destination boundary");
        require(m.sim.bus().peek8(dest)==(valid?0x60:before),"destination failure leaves bytes unchanged");
    }
    // Overlap has snapshot/memmove semantics.
    for (unsigned i=0;i<8;++i)m.sim.bus().write8(0x2100+i,i);
    m.word(0x100,0x2100);m.word(0x102,0x2102);m.word(0x104,6);
    require(m.call(SYS_COPY)==6 && !m.failed(),"overlap result");
    for(unsigned i=0;i<6;++i)require(m.sim.bus().peek8(0x2102+i)==i,"overlap snapshot");
    // Above-limit lengths and parameter blocks spanning into a vacant window.
    m.word(0x104,257);require(m.call(SYS_COPY)==uint16_t(SYS_EINVAL) && m.failed(),"copy bound");
    require(m.call(SYS_COPY,0x7FFF)==uint16_t(SYS_EFAULT) && m.failed(),"parameter boundary");
    m.word(0x100,token); require(m.call(SYS_BANK_FREE)==0 && !m.failed(),"free mapped resource");
    require(m.sim.bus().peek8(MMU1)==DISCARD_FRAME,"revoke before free");
    require(m.call(SYS_BANK_FREE)==uint16_t(SYS_ESTALE) && m.failed(),"stale identity");
    require(m.sim.bus().peek8(FREE_COUNT)==28,"accounting after copies");
    // Exhaust real frame admission, then verify every release restores accounting.
    std::array<uint16_t,28> handles{};
    for(auto& handle:handles){ handle=m.call(SYS_BANK_ALLOC);require(!m.failed(),"allocate every free frame"); }
    require(m.call(SYS_BANK_ALLOC)==uint16_t(SYS_ENOMEM) && m.failed(),"exhaustion");
    for(auto handle:handles){m.word(0x100,handle);require(m.call(SYS_BANK_FREE)==0 && !m.failed(),"release exhausted pool");}
    require(m.sim.bus().peek8(FREE_COUNT)==28,"exhaustion rollback/accounting");
    unsigned low=KERNEL_STACK;
    for(unsigned a=KERNEL_CANARY+2;a<KERNEL_STACK;++a)if(m.sim.bus().peek8(a)!=0xCD){low=a;break;}
    require(m.sim.bus().peek8(KERNEL_CANARY)==0xA5 && m.sim.bus().peek8(KERNEL_CANARY+1)==0x5A,"kernel stack sentinel");
    std::cout<<"observed kernel stack bytes="<<KERNEL_STACK-low<<'\n';
    low=APP_STACK;
    for(unsigned a=APP_STACK-1024;a<APP_STACK;++a)if(m.sim.bus().peek8(a)!=0xCD){low=a;break;}
    std::cout<<"observed application entry stack bytes="<<APP_STACK-low<<'\n';
}

void irq_and_faults(const cli::LoadedImage& image,const cli::HardwareConfig& config,bool micro) {
    Machine m(image,config,micro);m.boot();
    auto& bus=m.sim.bus();auto& r=m.sim.cpu().regs();
    m.uart->inject_rx(0x61);
    require(bus.read8(UART+3)==0x61 && !(m.uart->status_a()&1),"locked read drains FIFO");
    // Configure shared ACR/IMR through the actual ROM backend in kernel context.
    bus.read8(0xFFFA,BusCycleKind::VectorRead);
    bus.write8(UART_ACR_SHADOW,0x8B); bus.write8(UART_IMR_SHADOW,0x02);
    bus.write8(MMU0,0); r.s=KERNEL_STACK; r.pc=ROM_TIMER_ENABLE;
    m.word(KERNEL_STACK,0x0000); // Stop on core start before executing it again.
    m.until([&]{return r.pc==0;},"ROM timer configuration");
    require(bus.peek8(UART_ACR_SHADOW)==0xFB && bus.peek8(UART_IMR_SHADOW)==0x0A,"shared controls preserved");
    // No RX input, so only timer can request IRQ. Return to the application.
    bus.write8(MMU0,APP_FRAME); bus.write8(GATE,0);
    r.s=APP_STACK;r.pc=app_done;r.cc=CC_F; // IRQ enabled.
    m.until([&]{return bus.peek8(IRQ_COUNT+1)>=2 && r.pc==app_done;},"application IRQ bridge",50000);
    require(!bus.privileged() && bus.peek8(MMU0)==APP_FRAME && r.s==APP_STACK,"IRQ outer return");
    // Pending timer at a privileged point, IRQ handler must return privileged.
    bus.read8(0xFFFA,BusCycleKind::VectorRead);bus.write8(MMU0,0);
    r.s=KERNEL_STACK;r.pc=0x3800;r.cc=CC_F;
    bus.write8(0x3800,0x12); // kernel NOP
    m.sim.tick_clock(5000);
    const auto before=bus.peek8(IRQ_COUNT+1);
    m.until([&]{return bus.peek8(IRQ_COUNT+1)!=before && r.pc==0x3800;},"kernel IRQ bridge");
    require(bus.privileged() && bus.peek8(MMU0)==0 && r.s==KERNEL_STACK,"IRQ nested privilege/maps");
    bus.write8(MMU2,7);require(bus.peek8(MMU2)==7,"write after nested IRQ");
    // IRQ nested inside an active syscall has a second independent entry record.
    bus.write8(MMU0,APP_FRAME);bus.write8(GATE,0);
    bus.write8(0x2000,0x3F);r.pc=0x2000;r.s=APP_STACK;r.a=SYS_PROBE;r.cc=CC_F;
    m.until([&]{return r.pc==sc_probe && bus.peek8(ENTRY_DEPTH)==1;},"pause active syscall");
    const auto saved_s=r.s;
    const auto nested_before=bus.peek8(IRQ_COUNT+1);
    m.sim.tick_clock(5000);r.cc&=~CC_I;
    m.until([&]{return bus.peek8(IRQ_COUNT+1)!=nested_before && r.pc==sc_probe;},"IRQ within syscall");
    require(bus.privileged() && bus.peek8(ENTRY_DEPTH)==1 && r.s==saved_s,"nested IRQ record/stack");
    m.until([&]{return r.pc==rt_rti && bus.peek8(ENTRY_DEPTH)==0;},"outer syscall at RTI");
    require(!bus.privileged(),"exit transaction must relock before RTI");
    m.until([&]{return r.pc==0x2001;},"outer syscall after IRQ");
    require(!bus.privileged() && bus.peek8(ENTRY_DEPTH)==0 && r.s==APP_STACK,"outer relock after nested IRQ: priv="+std::to_string(bus.privileged())+" depth="+std::to_string(bus.peek8(ENTRY_DEPTH))+" S="+std::to_string(r.s));
    // Reserved NMI switches to emergency stack and repeated NMI stays bounded.
    m.sim.cpu().set_nmi_line(true);
    m.until([&]{return r.pc==rom_halt;},"NMI bounded stop");
    require(bus.peek8(PANIC_REASON)==0x34 && r.s==EMERGENCY_STACK,"NMI diagnostics");
    for(unsigned repeat=0;repeat<100;++repeat){
        m.sim.cpu().set_nmi_line(false);m.sim.cpu().set_nmi_line(true);
        m.step();
        m.until([&]{return r.pc==rom_halt;},"repeated NMI stop");
        require(r.s==EMERGENCY_STACK,"repeated NMI resets emergency stack");
    }

    // Reset must establish its first maps without relying on the interrupted map/S.
    m.serial.clear();
    bus.write8(MMU0,31);bus.write8(MMU1,30);bus.write8(MMU2,29);bus.write8(MMU3,28);
    bus.write8(GATE,0);m.sim.reset_from_vector();m.boot();
    require(bus.peek8(UART_IMR_SHADOW)==0 && bus.peek8(UART_ACR_SHADOW)==0x80,"reset shared shadows");
    require(bus.peek8(IRQ_CONTROL)==0xF0,"reset IRQ filter");

    Machine overflow(image,config,micro);overflow.boot();
    overflow.sim.bus().write8(ENTRY_DEPTH,ENTRY_MAX);
    overflow.sim.bus().write8(0x2000,0x3F);overflow.sim.cpu().regs().pc=0x2000;
    overflow.until([&]{return overflow.sim.cpu().regs().pc==rom_halt;},"entry overflow stop");
    require(overflow.sim.bus().peek8(PANIC_REASON)==0x35,"depth diagnostics");

    Machine firq(image,config,micro);firq.boot();
    auto& f=firq.sim.cpu().regs();f.pc=app_done;f.cc=CC_I;f.s=APP_STACK;
    firq.sim.cpu().set_firq_line(true);
    firq.until([&]{return f.pc==rom_firq;},"FIRQ default");
    firq.sim.cpu().set_firq_line(false);
    firq.until([&]{return f.pc==app_done;},"FIRQ return");
    require(f.s==APP_STACK && !firq.sim.bus().privileged(),"FIRQ short-frame/permission");

    for(uint8_t opcode:{0x10,0x11,0x00}) {
        Machine fault(image,config,micro);fault.boot();
        auto& fr=fault.sim.cpu().regs();auto& fb=fault.sim.bus();
        // SWI2/SWI3 and illegal instruction all bridge through plain SWI.
        if(opcode){fb.write8(0x2000,opcode);fb.write8(0x2001,0x3F);}
        else {fb.write8(0x2000,0x15);}
        fr.pc=0x2000;fr.s=APP_STACK;fr.cc=CC_F;
        fault.until([&]{return fr.pc==rom_halt;},"unsupported/trap stop");
        require(fb.peek8(PANIC_REASON)==0x31 && fr.s==EMERGENCY_STACK,"fault diagnostics");
    }
}
int main(int argc,char**argv) {
    try {
        require(argc==4,"runner ROM config CMOC-app");
        std::string error;auto config=cli::load_hardware_config(argv[2],error);
        auto image=cli::load_image(argv[1],cli::RomFormat::Ihex);
        require(bool(config)&&bool(image),"load target: "+error);
        for(bool micro:{false,true}){
            Machine m(*image,*config,micro);m.boot();boundaries(m);
            irq_and_faults(*image,*config,micro);
            Machine c(*image,*config,micro);c.boot();
            std::ifstream input(argv[3],std::ios::binary);
            const std::string bytes((std::istreambuf_iterator<char>(input)),{});
            require(input.eof() || bool(input),"load CMOC application");
            require(!bytes.empty() && bytes.size()<=0x3600,"CMOC application bound");
            for(unsigned i=0;i<bytes.size();++i)c.sim.bus().write8(APP_START+i,uint8_t(bytes[i]));
            c.sim.bus().write8(TEST_RESULT,0);
            c.sim.cpu().regs().pc=APP_START;c.sim.cpu().regs().s=APP_STACK;c.sim.cpu().regs().dp=0;
            c.until([&]{return c.sim.bus().peek8(TEST_RESULT)==0xA5;},"CMOC syscall client");
            require(!c.sim.bus().privileged() && c.sim.bus().peek8(FREE_COUNT)==28,"CMOC resources/relock");
            std::cout<<(micro?"microcycle":"instruction")<<": MLOS contracts PASS\n";
        }
        return 0;
    }catch(const std::exception& e){std::cerr<<"MLOS FAIL: "<<e.what()<<'\n';return 1;}
}
