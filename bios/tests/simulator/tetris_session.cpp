// Optional fast headless driver for the simulator GUI's production backend.
// Each run budget is CPU cycles. Joystick input drives actual external VIA pins.
#include "microlind/app/sim_session.hpp"
#include "microlind/app/vdc_render.hpp"
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>

using microlind::app::SimSession;

template <class Range> static std::string hex(const Range& bytes)
{
    std::ostringstream out;
    for (auto value : bytes) out << std::hex << std::setfill('0') << std::setw(2) << unsigned(value);
    return out.str();
}

int main(int argc, char **argv)
{
    if (argc != 3) return 2;
    SimSession session(microlind::CpuMode::HD6309);
    if (!session.load_hardware_config(argv[2]) ||
        !session.load_rom(argv[1], microlind::cli::RomFormat::Ihex, 0xE000)) return 2;
    session.reset();
    std::string line;
    while (std::getline(std::cin, line)) {
        std::istringstream in(line);
        std::string command;
        in >> command;
        if (command == "run") {
            uint64_t cycles; in >> cycles;
            session.run_realtime_cycles(cycles);
        } else if (command == "send") {
            std::string bytes; in >> bytes;
            std::vector<uint8_t> data;
            for (std::size_t i = 0; i < bytes.size(); i += 2)
                data.push_back(uint8_t(std::stoul(bytes.substr(i, 2), nullptr, 16)));
            session.inject_serial_bytes(data);
        } else if (command == "joy") {
            unsigned pressed; in >> pressed;
            session.set_parallel_input_bits(true, 31, uint8_t(~pressed));
        } else if (command == "poke") {
            unsigned address, value; in >> std::hex >> address >> value;
            session.write_memory(uint16_t(address), uint8_t(value));
        } else if (command == "fill") {
            unsigned address, count, value; in >> std::hex >> address >> count >> value;
            for (unsigned i = 0; i < count; ++i)
                session.write_memory(uint16_t(address + i), uint8_t(value));
        } else if (command == "memory") {
            std::string tag; unsigned address, count;
            in >> tag >> std::hex >> address >> count;
            std::vector<uint8_t> data;
            for (unsigned i = 0; i < count; ++i) data.push_back(session.peek_memory(uint16_t(address + i)));
            std::cout << "{\"tag\":\"" << tag << "\",\"memory\":\"" << hex(data) << "\"}\n";
        } else if (command == "snapshot") {
            std::string tag; in >> tag;
            auto vdc = session.vdc_snapshot();
            auto via = session.parallel_snapshot();
            const auto& cpu = session.simulator().cpu().regs();
            std::vector<uint8_t> glyph(vdc.character_data.begin() + 127 * 16,
                                       vdc.character_data.begin() + 128 * 16);
            std::cout << "{\"tag\":\"" << tag << "\",\"serial\":\"" << hex(session.serial_tx())
                << "\",\"chars\":\"" << hex(vdc.chars) << "\",\"attrs\":\"" << hex(vdc.attrs)
                << "\",\"glyph\":\"" << hex(glyph) << "\",\"cursor\":" << unsigned(vdc.registers[10])
                << ",\"color\":" << unsigned(vdc.registers[26]) << ",\"dp\":" << unsigned(cpu.dp)
                << ",\"cc\":" << unsigned(cpu.cc) << ",\"stack\":" << cpu.s
                << ",\"acr\":" << unsigned(via.acr) << ",\"ddrb\":" << unsigned(via.ddr_b)
                << ",\"orb\":" << unsigned(via.output_b) << ",\"ier\":" << unsigned(via.ier)
                << ",\"t1_latch\":" << via.timer1_latch
                << ",\"edges\":" << via.pb7_transition_count << "}\n";
        } else if (command == "frame") {
            std::string path; in >> path;
            auto frame = microlind::app::render_vdc_framebuffer(session.vdc_snapshot(), 0.0);
            std::ofstream out(path, std::ios::binary);
            out << "P6\n" << frame.width << ' ' << frame.height << "\n255\n";
            for (std::size_t i = 0; i < frame.rgba.size(); i += 4)
                out.write(reinterpret_cast<const char*>(frame.rgba.data() + i), 3);
        } else if (!command.empty()) return 2;
    }
}
