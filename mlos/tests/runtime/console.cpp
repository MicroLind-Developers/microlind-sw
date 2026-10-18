#define main diagnostic_main
#include "runner.cpp"
#undef main
void dump(Machine &m) {
  std::cerr << "OUTPUT: " << m.output << "\nLOG: " << m.logs << "\n";
  std::cerr << "FS pid=" << m.word(FS_OWNER)
            << " failed=" << unsigned(m.sim.bus().peek8(FS_FAILED))
            << " flags=" << unsigned(m.sim.bus().peek8(FS_VOLUME_FLAGS))
            << " gens=" << m.word(FS_VOLUME_GENERATIONS) << ","
            << m.word(FS_VOLUME_GENERATIONS + 2) << "\n";
  for (int q = 0; q < 8; q++)
    std::cerr << "PCB " << q << " state="
              << unsigned(m.sim.bus().peek8(PROC_TABLE + q * PROC_SIZE))
              << " pid=" << m.word(PROC_TABLE + q * PROC_SIZE + P_PID)
              << " cwdvol=" << m.word(PROC_TABLE + q * PROC_SIZE + P_CWD_VOLUME)
              << " cwdgen="
              << m.word(PROC_TABLE + q * PROC_SIZE + P_CWD_GENERATION)
              << " exit=" << m.word(PROC_TABLE + q * PROC_SIZE + P_EXIT)
              << "\n";
}
void type(Machine &m, const std::string &line) {
  for (auto b : line) {
    m.serial->inject_rx(uint8_t(b));
    for (int i = 0; i < 300; i++)
      m.step();
  }
}
void command(Machine &m, const std::string &line, const std::string &expected,
             bool allow_error = false) {
  auto start = m.output.size();
  type(m, line + "\r");
  try {
    m.until(
        [&] {
          auto found = m.output.find(expected, start);
          return found != std::string::npos &&
                 m.output.find(" > ", found) != std::string::npos;
        },
        "console command " + line, 100000000);
    check(allow_error || m.output.find("error ", start) == std::string::npos,
          "command error: " + line);
  } catch (...) {
    dump(m);
    throw;
  }
}
int main(int argc, char **argv) {
  try {
    check(argc == 6, "console runner ROM/config/two pristine images");
    std::string error;
    auto cfg = cli::load_hardware_config(argv[2], error);
    auto rom = cli::load_image(argv[1], cli::RomFormat::Ihex);
    check(bool(cfg) && bool(rom), error);
    for (bool micro : {false, true}) {
      if (std::string(argv[5]) != "both" &&
          std::string(argv[5]) != (micro ? "microcycle" : "instruction"))
        continue;
      std::filesystem::copy_file(
          argv[3], cfg->cf.image_path,
          std::filesystem::copy_options::overwrite_existing);
      std::filesystem::copy_file(
          argv[4], cfg->cf2.image_path,
          std::filesystem::copy_options::overwrite_existing);
      Machine m(*rom, *cfg, micro);
      try {
        try {
          m.until([&] { return m.serial->rgb_led().green; },
                  "power LED before memory/storage initialization", 100);
          check(m.sim.clock().total_cycles() <= 32 &&
                    !m.serial->rgb_led().red && !m.serial->rgb_led().blue,
                "green power LED in first reset instructions");
          m.until([&] { return m.sim.cpu().regs().pc == rboot_clear; },
                  "feedback before common RAM clear", 10000);
          check(m.output == "MLOS boot\r\nClearing memory...",
                "early UART banner before RAM clear");
          m.until([&] { return m.output.find("/ > ") != std::string::npos; },
                  "CF console boot", 20000000);
          auto validating = m.output.find("Checking filesystem...");
          auto next = m.output.find("\r\n", validating);
          check(validating != std::string::npos && next != std::string::npos &&
                    next - validating > std::string("Checking filesystem...").size(),
                "activity pulses during filesystem validation (count follows duration)");
          check(m.output.find("Boot complete\r\nMLOS console\r\n") != std::string::npos &&
                    !m.sim.bus().peek8(BOOT_FEEDBACK_ACTIVE),
                "boot feedback ends before interactive console");
        } catch (...) {
          dump(m);
          throw;
        }
        command(m, "echo 'hello world'", "hello world\r\n");
        command(m, "echo '>'", ">\r\n");
        auto quiet = m.output.size();
        command(m, "sleep 1100", "/ > ");
        check(m.output.find('.', quiet) == std::string::npos,
              "no boot heartbeat leaks into the running console");
        command(m, "argtest alpha 'beta gamma'", "CMOC argv/BSS/heap PASS");
        command(m, "echo persistent > note", "/ > ");
        command(m, "cat note", "persistent\r\n");
        command(m, "cat<note>copy", "/ > ");
        command(m, "cat copy", "persistent\r\n");
        command(m, "cat /proc/memory", "frames=32");
        command(m, "mkdir testdir", "/ > ");
        command(m, "cd testdir", "/testdir");
        command(m, "pwd", "/testdir\r\n");
        command(m, "cd /", "/ > ");
        command(m, "cat note", "persistent\r\n");
        command(m, "fstest", "MLFS growth/locks/cwd PASS");
        command(m, "recover /disk1", "/ > ");
        command(m, "cat /disk1/seed", "second drive");
        auto dualstart = m.output.size();
        m.second->set_command_delay_cycles(1500000);
        type(m, "dualtest\r");
        bool healthy_completed_while_pending = false;
        m.until(
            [&] {
              // Observe overlap at completion publication; faster UART/kernel
              // paths may sample an idle gap between CF2 commands at the text.
              if (m.second->snapshot().status & 0x88) {
                for (unsigned q = 0; q < REQUEST_COUNT; ++q) {
                  auto rec = REQUEST_TABLE + q * REQUEST_SIZE;
                  if (m.sim.bus().peek8(rec + R_STATE) == RQ_COMPLETE &&
                      m.sim.bus().peek8(rec + R_DEVICE) == 0)
                    healthy_completed_while_pending = true;
                }
              }
              return m.output.find("healthy root during pending drive",
                                   dualstart) != std::string::npos;
            },
            "healthy filesystem progresses during second controller wait",
            30000000);
        check(healthy_completed_while_pending,
              "healthy root completion observed while second controller pending");
        check(m.free() == 0,
              "minimum-machine fully admitted two-drive workload");
        m.second->set_command_delay_cycles(0);
        m.until(
            [&] {
              return m.output.find("dual drive progress PASS", dualstart) !=
                         std::string::npos &&
                     m.output.find(
                         "/ > ", m.output.find("dual drive progress PASS",
                                               dualstart)) != std::string::npos;
            },
            "both filesystem workers complete", 30000000);
        command(m, "echo separate > /disk1/note", "/ > ");
        command(m, "cat /disk1/note", "separate");
        command(m, "unmount /disk1", "/ > ");
        command(m, "recover /disk1", "/ > ");
        command(m, "cat /disk1/note", "separate");
        command(m, "cd /disk1", "/disk1 > ");
        command(m, "unmount /disk1", "error -7", true);
        command(m, "cd /", "/ > ");
        command(m, "unmount /disk1", "/ > ");
        check(m.second->load_disk_image(cfg->cf2.image_path.string() + ".dirty", &error), error);
        command(m, "recover /disk1", "/ > ");
        command(m, "cat /disk1/seed", "second drive");
        command(m, "echo refused > /disk1/refused", "launch error -24", true);
        command(m, "unmount /disk1", "/ > ");
        check(m.second->load_disk_image(cfg->cf2.image_path, &error), error);
        check(m.logs.find("MLOS init") != std::string::npos,
              "independent UART B logs");
        auto start = m.output.size();
        type(m, "key\r");
        m.until(
            [&] {
              return m.output.find("key ready", start) != std::string::npos;
            },
            "raw key command", 20000000);
        type(m, "\033[A");
        m.until(
            [&] {
              return m.output.find("key=256", start) != std::string::npos &&
                     m.output.find("/ > ", m.output.find("key=256", start)) !=
                         std::string::npos;
            },
            "shared raw key decoder", 20000000);
        start = m.output.size();
        type(m, "sleep 5000\r");
        m.until([&] { return m.word(T_FG) != m.word(T_SHELL); },
                "foreground handoff", 20000000);
        type(m, std::string(1, 3));
        m.until(
            [&] {
              return m.output.find("error 130", start) != std::string::npos &&
                     m.output.find("/ > ", m.output.find("error 130", start)) !=
                         std::string::npos;
            },
            "Ctrl-C restores shell", 20000000);
        command(m, "echo survived", "survived\r\n");
        start = m.output.size();
        type(m, "staletest\r");
        m.until(
            [&] {
              return m.output.find("stale test ready", start) !=
                     std::string::npos;
            },
            "stale descriptor setup", 30000000);
        check(m.second != nullptr, "second CF instance");
        m.second->unload_disk_image();
        type(m, "\r");
        m.until(
            [&] {
              return m.output.find("healthy root after drive failure", start) !=
                     std::string::npos;
            },
            "affected-volume failure isolation", 30000000);
        check(m.second->load_disk_image(cfg->cf2.image_path, &error), error);
        type(m, "\r");
        m.until(
            [&] {
              return m.output.find("volume recovery/stale PASS", start) !=
                         std::string::npos &&
                     m.output.find("/ > ",
                                   m.output.find("volume recovery/stale PASS",
                                                 start)) != std::string::npos;
            },
            "explicit recovery uses fresh descriptors", 30000000);
        start = m.output.size();
        type(m, "cp /grow /cancelled\r");
        m.until(
            [&] {
              return m.word(T_FG) != m.word(T_SHELL) &&
                     m.sim.bus().peek8(DEVICE_TABLE + D_ACTIVE) != 0xFF;
            },
            "foreground file work owns a pending request", 30000000);
        type(m, std::string(1, 3));
        m.until(
            [&] {
              return m.output.find("error 130", start) != std::string::npos &&
                     m.output.find("/ > ", m.output.find("error 130", start)) !=
                         std::string::npos;
            },
            "Ctrl-C file work keeps accepted requests safe", 30000000);
        command(m, "echo after-file-cancel", "after-file-cancel\r\n");
        // The frontend sleeps on its listener now. Wake it with actual work
        // before injecting its service-failure trap at an application boundary.
        start = m.output.size();
        type(m, "ls\r");
        m.ready(2);
        m.sim.bus().write8(0x2000, 0x10);
        m.sim.bus().write8(0x2001, 0x3F);
        m.sim.cpu().regs().pc = 0x2000;
        m.until(
            [&] {
              return m.sim.bus().peek8(FS_FAILED) &&
                     m.sim.bus().peek8(DEVICE_TABLE + D_ACTIVE) == 0xFF;
            },
            "filesystem service failure withdraws workers", 30000000);
        m.until([&] { return m.output.find(" > ", start) != std::string::npos; },
                "pending filesystem client returns after service failure", 30000000);
        command(m, "cat /proc/memory", "frames=32");
        command(m, "echo diagnostics-alive", "diagnostics-alive\r\n");
        command(m, "cat /proc/mounts", "failed=1");
        command(m, "exit", "MLOS console\r\n");
        start = m.output.size();
        type(m, "exit\r");
        m.until(
            [&] {
              return m.output.find("shell failed twice", start) !=
                     std::string::npos;
            },
            "one shell restart then emergency diagnostics", 30000000);
        std::cout << (micro ? "microcycle" : "instruction")
                  << ": CF/init/CMOC/shell/files/redirection PASS\n";
        guards(m);
      } catch (...) {
        dump(m);
        throw;
      }
    }
    return 0;
  } catch (std::exception &e) {
    std::cerr << "console FAIL: " << e.what() << '\n';
    return 1;
  }
}
