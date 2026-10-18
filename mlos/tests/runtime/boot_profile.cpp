// Read-only observation of cold boot; target code and scheduling are unchanged.
#define main runtime_contract_main
#include "runner.cpp"
#undef main
#include <chrono>
#include <set>
struct Milestone {
  std::string name;
  uint64_t cycles, instruction_steps;
  uint16_t pc, pid;
};
int main(int argc, char **argv) {
  try {
    check(argc == 4, "boot profiler ROM/config/engine");
    std::string error;
    auto cfg = cli::load_hardware_config(argv[2], error);
    auto rom = cli::load_image(argv[1], cli::RomFormat::Ihex);
    check(bool(cfg) && bool(rom), error);
    bool micro = std::string(argv[3]) == "microcycle";
    check(micro || std::string(argv[3]) == "instruction", "engine");
    Machine m(*rom, *cfg, micro);
    const auto start = m.sim.clock().total_cycles();
    const auto wall = std::chrono::steady_clock::now();
    uint64_t instruction_steps = 0;
    std::set<std::string> seen;
    std::vector<Milestone> events;
    std::vector<uint64_t> pulse_cycles;
    auto mark = [&](const std::string &name) {
      if (seen.insert(name).second)
        events.push_back({name, m.sim.clock().total_cycles() - start, instruction_steps,
                          m.sim.cpu().regs().pc, m.word(CURRENT_PID)});
    };
    auto named = [&](uint16_t p) {
      std::string name;
      for (unsigned i = 0; i < 48; ++i) {
        auto c = m.sim.bus().peek8(p + i);
        if (!c) break;
        name += char(c);
      }
      return name;
    };
    mark("reset_entry");
    while (instruction_steps < 20000000) {
      const auto pc = m.sim.cpu().regs().pc;
      const auto pid = m.word(CURRENT_PID);
      const bool privileged = m.sim.bus().privileged();
      if (m.serial->rgb_led().green) mark("power_led_on");
      if (privileged) {
        if (pc == rboot_clear) mark("common_clear_start");
        if (pc == rboot_clear + 7) mark("common_clear_complete");
        if (pc == rom_uart_init) mark("uart_setup_start");
        if (pc == boot_identify) mark("cf_identify_start");
        if (pc == boot_open_root) mark("partition_validation_start");
        if (pc == boot_kernel) mark("kernel_lookup_start");
        if (pc == bk_copy) mark("kernel_payload_start");
        if (pc == bk_verify) mark("kernel_checksum_start");
        if (pc == 0) mark("kernel_entry");
        if (pc == process_init) mark("process_metadata_start");
        if (pc == backplane_init) mark("backplane_setup_start");
        if (pc == driver_init) mark("driver_setup_start");
        if (pc == runtime_fill_kernel) mark("stack_fill_start");
        if (pc == process_spawn) {
          if (!pid) mark("init_image_load_start");
          else {
            auto name = named(m.sim.cpu().regs().x);
            if (name == "filesystem.mlx") mark("filesystem_image_load_start");
            if (name == "fs0.mlx") mark("worker_image_load_start");
            if (name == "shell.mlx") mark("shell_image_load_start");
          }
        }
        if (pc == rom_timer_enable) mark("timer_enable_start");
        if (pc == sl_return && !(m.sim.cpu().regs().cc & 1)) {
          if (pid == 3) mark("worker_listener_ready");
          if (pid == 2) mark("filesystem_listener_ready");
        }
      } else if (pc == 0x400) {
        if (pid == 1) mark("init_first_instruction");
        if (pid == 2) mark("filesystem_first_instruction");
        if (pid == 3) mark("worker_first_instruction");
        if (pid == 4) mark("shell_first_instruction");
      }
      if (!privileged && pid == 3) {
        if (pc == worker_FS_MOUNT) mark("worker_mount_start");
        if (pc == worker_volume_validate) mark("worker_validation_start");
      }
      if (m.logs.find("MLOS init\r\n") != std::string::npos) mark("init_log_complete");
      if (seen.contains("worker_first_instruction") &&
          m.word(FS_OWNER) == 2 && (m.sim.bus().peek8(FS_VOLUME_FLAGS) & 1))
        mark("root_volume_online");
      if (!m.output.empty()) mark("first_console_byte");
      if (m.output.find("MLOS console\r\n") != std::string::npos) mark("console_banner_complete");
      if (m.output.find("Boot complete\r\n") != std::string::npos) mark("boot_feedback_complete");
      if (m.output.find("/ > ") != std::string::npos) {
        mark("prompt_complete");
        break;
      }
      auto output_size = m.output.size();
      m.step();
      if (m.output.size() > output_size && m.sim.cpu().regs().pc == rbp_done) {
        check(m.sim.bus().peek8(BOOT_FEEDBACK_ACTIVE), "no progress pulse after console handoff");
        pulse_cycles.push_back(m.sim.clock().total_cycles() - start);
      }
      ++instruction_steps;
    }
    if (!seen.contains("prompt_complete")) {
      std::cerr << "CPU model=" << cfg->cpu_hz << " Hz, PC=" << std::hex
                << m.sim.cpu().regs().pc << " S=" << m.sim.cpu().regs().s
                << " PID=" << m.word(CURRENT_PID) << std::dec
                << " ticks=" << m.word(TICKS + 2) << "\n" << m.output << "\n";
    }
    check(seen.contains("prompt_complete"), "cold boot must reach prompt");
    check(!m.sim.bus().peek8(FS_FAILED) && (m.sim.bus().peek8(FS_VOLUME_FLAGS) & 1),
          "boot must include a healthy root filesystem");
    check(!m.sim.bus().peek8(BOOT_FEEDBACK_ACTIVE), "boot feedback stops at console handoff");
    const auto elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - wall).count();
    std::cout << "{\"engine\":\"" << argv[3] << "\",\"cpu_hz\":" << cfg->cpu_hz
              << ",\"host_elapsed_seconds\":" << elapsed << ",\"events\":[";
    bool first = true;
    for (const auto &e : events) {
      if (!first) std::cout << ',';
      first = false;
      std::cout << "{\"name\":\"" << e.name << "\",\"cycles\":" << e.cycles
                << ",\"instruction_steps\":" << e.instruction_steps << ",\"pc\":" << e.pc
                << ",\"pid\":" << e.pid << '}';
    }
    std::cout << "],\"console\":\"";
    for (auto c : m.output) {
      if (c == '\r') std::cout << "\\r";
      else if (c == '\n') std::cout << "\\n";
      else if (c == '"' || c == '\\') std::cout << '\\' << c;
      else std::cout << c;
    }
    std::cout << "\",\"pulse_cycles\":[";
    for (unsigned i = 0; i < pulse_cycles.size(); ++i) {
      if (i) std::cout << ',';
      std::cout << pulse_cycles[i];
    }
    std::cout << "]}\n";
    return 0;
  } catch (const std::exception &e) {
    std::cerr << "boot profile failed: " << e.what() << '\n';
    return 1;
  }
}
