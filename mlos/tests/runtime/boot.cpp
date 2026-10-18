#define main diagnostic_main
#include "runner.cpp"
#undef main
int main(int argc, char **argv) {
  try {
    check(argc >= 3, "boot runner ROM/rejected configs");
    auto rom = cli::load_image(argv[1], cli::RomFormat::Ihex);
    check(bool(rom), "ROM");
    for (int i = 2; i < argc; i++) {
      std::string error;
      auto cfg = cli::load_hardware_config(argv[i], error);
      check(bool(cfg), error);
      for (bool micro : {false, true}) {
        Machine m(*rom, *cfg, micro);
        m.until([&] { return m.sim.cpu().regs().pc == rom_halt; }, "boot rejection");
        auto diagnostic = m.output.rfind("\r\nB");
        check(diagnostic != std::string::npos && diagnostic + 6 == m.output.size() &&
                  m.output[diagnostic + 3] >= '1' && m.output[diagnostic + 3] <= '3',
              "bounded boot diagnostic");
        check(m.serial->rgb_led().red && !m.serial->rgb_led().green &&
                  !m.serial->rgb_led().blue,
              "failed boot leaves red power LED");
        for (int j = 0; j < 1000; j++)
          m.step();
        check(m.word(CURRENT_PID) == 0 &&
                  !m.sim.bus().peek8(PROC_TABLE + P_STATE),
              "corrupt boot never executes kernel/process");
      }
    }
    std::cout << "boot rejection matrix: instruction + microcycle PASS\n";
    return 0;
  } catch (std::exception &e) {
    std::cerr << e.what() << '\n';
    return 1;
  }
}
