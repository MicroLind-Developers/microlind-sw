// Observe real shell commands over UART; no target patches or syscall
// injection.
#define main runtime_contract_main
#include "runner.cpp"
#undef main
#include <algorithm>
#include <array>
#include <chrono>
#include <iomanip>
#include <map>
#include <unordered_map>

const char *domains[] = {"core",    "rom",  "shell",     "filesystem", "worker",
                         "command", "init", "irq_entry", "idle",       "other"};
std::string json_string(const std::string &s) {
  std::string out = "\"";
  for (unsigned char c : s) {
    if (c == '\r')
      out += "\\r";
    else if (c == '\n')
      out += "\\n";
    else if (c == '\t')
      out += "\\t";
    else if (c == '\\' || c == '"') {
      out += '\\';
      out += char(c);
    } else if (c < 32) {
      constexpr char hex[] = "0123456789abcdef";
      out += "\\u00";
      out += hex[c >> 4];
      out += hex[c & 15];
    } else
      out += char(c);
  }
  return out + '"';
}
uint16_t program_main_for(const std::string &line) {
  const auto name = line.substr(0, line.find(' '));
  const std::pair<const char *, uint16_t> mains[] = {
      {"echo", echo_program_main}, {"pwd", pwd_program_main},
      {"ls", ls_program_main},     {"cat", cat_program_main},
      {"cp", cp_program_main},     {"mem", mem_program_main}};
  for (auto [key, pc] : mains)
    if (name == key)
      return pc;
  return command_program_main;
}
struct Stats {
  uint64_t start{}, steps{}, irqs{}, masked_cycles{}, mask_run{}, max_masked{},
      loader_calls{}, loader_active_calls{}, image_bytes{}, image_stores{},
      rom_reads{};
  uint16_t mask_pc{}, max_mask_pc{}, child{}, child_pcb{};
  bool loader_was_active{};
  std::array<uint64_t, 10> cycles{};
  std::array<uint64_t, 64> syscalls{};
  std::array<uint64_t, 10> domain_syscalls{};
  std::unordered_map<unsigned, uint64_t> pc_cycles;
  std::map<std::string, uint64_t> events;
  void event(const std::string &name, uint64_t now) {
    events.emplace(name, now - start);
  }
};
struct Perf : Machine {
  using Machine::Machine;
  uint16_t program_main_pc = command_program_main;
  uint64_t now() { return sim.clock().total_cycles(); }
  uint32_t longword(uint16_t p) {
    return (uint32_t(word(p)) << 16) | word(p + 2);
  }
  uint16_t pcb(uint16_t pid) {
    for (unsigned i = 0; i < PROC_COUNT; ++i)
      if (word(PROC_TABLE + i * PROC_SIZE + P_PID) == pid)
        return PROC_TABLE + i * PROC_SIZE;
    return 0;
  }
  void tick(Stats *s = nullptr) {
    if (!s) {
      step();
      return;
    }
    auto r = sim.cpu().regs();
    auto before = now();
    const bool irq = sim.cpu().irq_pending();
    const bool idle = sim.cpu().waiting_for_interrupt() && !irq;
    const bool privileged = sim.bus().privileged();
    auto pid = word(CURRENT_PID), shell = word(T_SHELL);
    unsigned domain = 9;
    if (irq)
      domain = 7;
    else if (idle)
      domain = 8;
    else if (r.pc >= 0xE000)
      domain = 1;
    else if (privileged && mapper->bank[0] == 0 && r.pc < 0x4000)
      domain = 0;
    else if (!privileged && r.pc < 0xC000) {
      if (pid == shell)
        domain = 2;
      else if (pid == 1)
        domain = 6;
      else if (pid == 2)
        domain = 3;
      else if (pid == 3)
        domain = 4;
      else
        domain = 5;
    }
    const bool user = domain >= 2 && domain <= 6;
    if (domain == 0) {
      if (r.pc == process_spawn)
        s->event("spawn_preflight", before);
      if (r.pc == ps_async_start)
        s->event("image_admitted", before);
      if (r.pc == loader_progress) {
        ++s->loader_calls;
        if (sim.bus().peek8(LOADER_ACTIVE))
          ++s->loader_active_calls;
      }
      if (r.pc == image_byte)
        ++s->image_bytes;
      if (r.pc == image_store)
        ++s->image_stores;
#ifdef PROFILE_CHUNK_LOADER
      if (r.pc == ir_copy)
        s->image_bytes += word(LOADER_RUN);
      if (r.pc == ir_map)
        s->image_stores += word(LOADER_RUN);
#endif
    }
    if (domain == 1 && r.pc == CF_READ_SECTOR)
      ++s->rom_reads;
    if (user && !irq && sim.bus().peek8(r.pc) == 0x3F) {
      if (r.a < s->syscalls.size())
        ++s->syscalls[r.a];
      ++s->domain_syscalls[domain];
      if (pid == shell && r.a == SYS_SPAWN)
        s->event("spawn_syscall", before);
      if (pid == s->child && r.a == SYS_WRITE)
        s->event("command_write_syscall", before);
      if (pid == s->child && r.a == SYS_EXIT)
        s->event("command_exit", before);
    }
    const bool active = sim.bus().peek8(LOADER_ACTIVE) != 0;
    if (active && !s->loader_was_active) {
      s->child_pcb = word(LOADER_PROC);
      s->child = word(s->child_pcb + P_PID);
      s->event("loader_active", before);
    }
    if (!active && s->loader_was_active) {
      if (sim.bus().peek8(s->child_pcb + P_STATE) == PS_FREE)
        s->event("image_cancelled", before);
      else
        s->event("image_loaded", before);
    }
    s->loader_was_active = active;
    if (domain == 5 && pid == s->child) {
      if (r.pc == 0x400)
        s->event("command_entry", before);
      if (r.pc == program_main_pc)
        s->event("command_main", before);
    }
    if (domain == 2 && s->events.contains("command_exit"))
      s->event("parent_resumed", before);
    step();
    const auto delta = now() - before;
    s->cycles[domain] += delta;
    if (!irq && !idle)
      s->pc_cycles[domain * 65536 + r.pc] += delta;
    ++s->steps;
    if (irq)
      ++s->irqs;
    if (r.cc & CC_I) {
      s->masked_cycles += delta;
      if (!s->mask_run)
        s->mask_pc = r.pc;
      s->mask_run += delta;
      if (s->mask_run > s->max_masked) {
        s->max_masked = s->mask_run;
        s->max_mask_pc = s->mask_pc;
      }
    } else
      s->mask_run = 0;
  }
  template <class F>
  void wait(F predicate, const std::string &why, Stats *s = nullptr,
            unsigned max_steps = 100000000) {
    for (unsigned i = 0; i < max_steps; ++i) {
      if (predicate())
        return;
      tick(s);
    }
    throw std::runtime_error(why +
                             " PC=" + std::to_string(sim.cpu().regs().pc) +
                             " output=" + output);
  }
  void settle() {
    auto end = now() + 300000;
    while (now() < end)
      tick();
    output.clear();
  }
  void type_line(const std::string &line) {
    settle();
    for (auto c : line)
      serial->inject_rx(uint8_t(c));
    wait([&] { return output == line; }, "line echo");
    output.clear();
  }
};
void emit(const std::string &label, const std::string &command, unsigned sample,
          Perf &m, Stats &s, uint32_t start_ticks, double wall,
          bool result_output) {
  uint64_t total = m.now() - s.start;
  uint64_t sum = 0;
  for (auto v : s.cycles)
    sum += v;
  check(sum == total, "exclusive cycle accounting");
  std::vector<std::pair<unsigned, uint64_t>> hot(s.pc_cycles.begin(),
                                                 s.pc_cycles.end());
  std::sort(hot.begin(), hot.end(),
            [](auto a, auto b) { return a.second > b.second; });
  std::array<unsigned, 10> emitted{};
  std::cout << "{\"type\":\"trial\",\"label\":" << json_string(label)
            << ",\"command\":" << json_string(command)
            << ",\"sample\":" << sample << ",\"cycles\":" << total
            << ",\"steps\":" << s.steps
            << ",\"host_seconds\":" << std::setprecision(9) << wall
            << ",\"irq_count\":" << s.irqs << ",\"delivered_ticks\":"
            << uint32_t(m.longword(TICKS) - start_ticks)
            << ",\"masked_cycles\":" << s.masked_cycles
            << ",\"max_masked_cycles\":" << s.max_masked
            << ",\"max_masked_start_pc\":" << s.max_mask_pc
            << ",\"loader_calls\":" << s.loader_calls
            << ",\"loader_active_calls\":" << s.loader_active_calls
            << ",\"image_bytes\":" << s.image_bytes
            << ",\"image_stores\":" << s.image_stores
            << ",\"rom_reads\":" << s.rom_reads
            << ",\"result_output\":" << (result_output ? "true" : "false")
            << ",\"output_bytes\":" << m.output.size()
            << ",\"child_pid\":" << s.child << ",\"events\":{";
  bool first = true;
  for (auto &[name, value] : s.events) {
    if (!first) {
      std::cout << ',';
    }
    first = false;
    std::cout << json_string(name) << ':' << value;
  }
  std::cout << "},\"domains\":{";
  for (unsigned i = 0; i < 10; ++i) {
    if (i) {
      std::cout << ',';
    }
    std::cout << json_string(domains[i]) << ':' << s.cycles[i];
  }
  std::cout << "},\"syscalls\":{";
  first = true;
  for (unsigned i = 0; i < s.syscalls.size(); ++i)
    if (s.syscalls[i]) {
      if (!first) {
        std::cout << ',';
      }
      first = false;
      std::cout << json_string(std::to_string(i)) << ':' << s.syscalls[i];
    }
  std::cout << "},\"domain_syscalls\":{";
  for (unsigned i = 0; i < 10; ++i) {
    if (i) {
      std::cout << ',';
    }
    std::cout << json_string(domains[i]) << ':' << s.domain_syscalls[i];
  }
  std::cout << "},\"hotspots\":[";
  first = true;
  for (auto [key, value] : hot) {
    auto d = key / 65536;
    if (emitted[d]++ >= 12)
      continue;
    if (!first) {
      std::cout << ',';
    }
    first = false;
    std::cout << "{\"domain\":" << json_string(domains[d])
              << ",\"pc\":" << (key % 65536) << ",\"cycles\":" << value << '}';
  }
  std::cout << "],\"pc_cycles\":[";
  first = true;
  for (auto [key, value] : hot) {
    if (!first) {
      std::cout << ',';
    }
    first = false;
    std::cout << '[' << key << ',' << value << ']';
  }
  std::cout << "],\"output\":" << json_string(m.output) << "}\n" << std::flush;
  std::cerr << label << " #" << sample << ": " << double(total) / 3000000
            << " s simulated\n";
}
void command_trial(Perf &m, const std::string &label,
                   const std::string &command, unsigned sample, bool has_output,
                   bool allow_error = false) {
  m.type_line(command);
  m.program_main_pc = program_main_for(command);
  Stats s;
  s.start = m.now();
  auto ticks = m.longword(TICKS);
  auto wall = std::chrono::steady_clock::now();
  s.event("enter", m.now());
  m.serial->inject_rx(13);
  m.wait(
      [&] {
        if (!m.output.empty())
          s.event("enter_echo", m.now());
        if (m.output.size() > 2 && has_output)
          s.event("first_result", m.now());
        return m.output.size() >= 6 && m.output.ends_with("/ > ");
      },
      "command " + command, &s);
  s.event("prompt", m.now());
  check(m.output.starts_with("\r\n"), "Enter echo is separated from result");
  check(allow_error || m.output.find("error ") == std::string::npos,
        "command success: " + command);
  if (label == "echo")
    check(m.output == "\r\nping\r\n/ > ", "echo result");
  if (label == "pwd")
    check(m.output == "\r\n/\r\n/ > ", "pwd result");
  if (label == "small_read" || label == "large_read") {
    unsigned size = label == "small_read" ? 128 : 4096;
    std::string expected;
    for (unsigned i = 0; i < size; ++i)
      expected += char('A' + i % 26);
    expected[126] = expected[size - 2] = '\r';
    expected[127] = expected[size - 1] = '\n';
    check(m.output == "\r\n" + expected + "/ > ", "file content: " + command);
  }
  emit(label, command, sample, m, s, ticks,
       std::chrono::duration<double>(std::chrono::steady_clock::now() - wall)
           .count(),
       has_output);
}
void key_trial(Perf &m, const std::string &label, uint8_t key,
               const std::string &expected) {
  m.settle();
  Stats s;
  s.start = m.now();
  auto ticks = m.longword(TICKS);
  auto wall = std::chrono::steady_clock::now();
  m.serial->inject_rx(key);
  m.wait(
      [&] {
        if (!m.output.empty())
          s.event("first_echo", m.now());
        return m.output == expected;
      },
      label, &s);
  s.event("echo_complete", m.now());
  emit(label, "", 0, m, s, ticks,
       std::chrono::duration<double>(std::chrono::steady_clock::now() - wall)
           .count(),
       false);
}
void cancel_trial(Perf &m, unsigned sample) {
  m.type_line("sleep 5000");
  m.serial->inject_rx(13);
  m.wait([&] { return m.word(T_FG) != m.word(T_SHELL); }, "foreground handoff");
  auto child = m.word(T_FG), record = m.pcb(child);
  check(record != 0, "sleep child record");
  m.wait(
      [&] {
        return m.sim.bus().peek8(record + P_STATE) == PS_SLEEP &&
               uint32_t(m.longword(record + P_WAKE) - m.longword(TICKS)) > 1000;
      },
      "foreground long sleep");
  m.output.clear();
  Stats s;
  s.start = m.now();
  s.child = child;
  s.child_pcb = record;
  auto ticks = m.longword(TICKS);
  auto wall = std::chrono::steady_clock::now();
  m.serial->inject_rx(3);
  m.wait(
      [&] {
        if (!m.output.empty())
          s.event("first_result", m.now());
        return m.output.ends_with("/ > ");
      },
      "foreground cancellation", &s);
  s.event("prompt", m.now());
  check(m.output.find("error 130") != std::string::npos, "Ctrl-C exit status");
  emit("ctrl_c", "sleep 5000 then Ctrl-C", sample, m, s, ticks,
       std::chrono::duration<double>(std::chrono::steady_clock::now() - wall)
           .count(),
       true);
}
// Ctrl-C while spawn still owns an unpublished loader transaction. This
// measures when the shell has consumed the interrupt and displays a stable
// prompt again.
void loading_cancel_trial(Perf &m, unsigned sample) {
  m.type_line("echo cancelled");
  m.program_main_pc = program_main_for("echo");
  const auto free_before = m.free();
  m.serial->inject_rx(13);
  m.wait([&] { return m.sim.bus().peek8(LOADER_ACTIVE) != 0; },
         "loader admission");
  auto end = m.now() + 750000;
  while (m.now() < end)
    m.tick();
  check(m.sim.bus().peek8(LOADER_ACTIVE) != 0, "loader still active at Ctrl-C");
  m.output.clear();
  Stats s;
  s.start = m.now();
  s.child_pcb = m.word(LOADER_PROC);
  s.child = m.word(s.child_pcb + P_PID);
  s.loader_was_active = true;
  auto ticks = m.longword(TICKS);
  auto wall = std::chrono::steady_clock::now();
  s.event("ctrl_c", m.now());
  m.serial->inject_rx(3);
  m.wait(
      [&] {
        if (!m.output.empty())
          s.event("first_result", m.now());
        if (m.output.ends_with("/ > "))
          s.event("first_prompt", m.now());
        return m.output.ends_with("^C\r\n/ > ");
      },
      "loading cancellation acknowledgement", &s);
  s.event("prompt", m.now());
  check(m.output == "^C\r\n/ > ",
        "pending launch cancelled before command output");
  check(!s.events.contains("command_entry"), "cancelled image never executed");
  check(m.free() == free_before, "cancelled image frames reclaimed");
  check(m.sim.bus().peek8(s.child_pcb + P_STATE) == PS_FREE,
        "cancelled image PCB reclaimed");
  emit("ctrl_c_loading", "echo cancelled then Ctrl-C during load", sample, m, s,
       ticks,
       std::chrono::duration<double>(std::chrono::steady_clock::now() - wall)
           .count(),
       true);
}
int main(int argc, char **argv) {
  try {
    check(argc == 6, "profiler ROM/config/engine/samples/filter");
    std::string error;
    auto cfg = cli::load_hardware_config(argv[2], error);
    auto rom = cli::load_image(argv[1], cli::RomFormat::Ihex);
    check(bool(cfg) && bool(rom), error);
    check(cfg->cpu_hz == 3000000, "3 MHz model required");
    bool micro = std::string(argv[3]) == "microcycle";
    unsigned samples = std::stoul(argv[4]);
    check(samples > 0 && samples <= 20, "samples1..20");
    // argv5 is an explicit scenario selection, '*' selects the complete suite.
    std::string filter = argv[5];
    auto selected = [&](const std::string &s) {
      return filter == "*" || filter == s;
    };
    Perf m(*rom, *cfg, micro);
    m.wait([&] { return m.output.ends_with("/ > "); }, "boot", nullptr,
           30000000);
    check(m.sim.bus().peek8(FS_VOLUME_FLAGS) & 1, "healthy root");
    std::cout << "{\"type\":\"boot\",\"cycles\":" << m.now()
              << ",\"engine\":" << json_string(argv[3]) << "}\n";
    if (selected("typing")) {
      key_trial(m, "key_echo", 'x', "x");
      key_trial(m, "backspace", 8, "\b \b");
    }
    struct Case {
      const char *label;
      const char *line;
      bool output, error;
    };
    const Case cases[] = {{"blank", "", false, false},
                          {"builtin_cd", "cd /", false, false},
                          {"missing", "no-such-command", true, true},
                          {"echo", "echo ping", true, false},
                          {"pwd", "pwd", true, false},
                          {"mem", "mem", true, false},
                          {"proc_read", "cat /proc/memory", true, false},
                          {"small_read", "cat /perf-small", true, false},
                          {"large_read", "cat /perf-large", true, false},
                          {"list", "ls /", true, false},
                          {"redirect", "echo ping > /perf-out", false, false},
                          {"copy", "cp /perf-large /perf-copy", false, false},
                          {"yield", "yield", false, false}};
    for (auto c : cases)
      if (selected(c.label))
        for (unsigned i = 0; i < samples; ++i)
          command_trial(m, c.label, c.line, i, c.output, c.error);
    if (selected("ctrl_c"))
      for (unsigned i = 0; i < samples; ++i)
        cancel_trial(m, i);
    if (selected("ctrl_c_loading"))
      for (unsigned i = 0; i < samples; ++i)
        loading_cancel_trial(m, i);
    if (selected("idle")) {
      m.settle();
      Stats s;
      s.start = m.now();
      auto ticks = m.longword(TICKS);
      auto wall = std::chrono::steady_clock::now();
      while (m.now() - s.start < 3000000)
        m.tick(&s);
      emit(
          "idle", "", 0, m, s, ticks,
          std::chrono::duration<double>(std::chrono::steady_clock::now() - wall)
              .count(),
          false);
    }
    check(m.word(KERNEL_CANARY) == 0xA55A && m.word(EMERGENCY_CANARY) == 0xA55A,
          "stack guards");
    return 0;
  } catch (const std::exception &e) {
    std::cerr << "response profiler failed: " << e.what() << '\n';
    return 1;
  }
}
