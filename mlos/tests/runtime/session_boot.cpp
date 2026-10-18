// Exercise the GUI session loader and realtime backend, including its CPU model.
#include "microlind/app/session_file.hpp"
#include "microlind/app/sim_session.hpp"
#include <iostream>
#include <stdexcept>
using namespace microlind;

int main(int argc, char **argv) {
  try {
    if (argc != 2)
      throw std::runtime_error("session path required");
    std::string error;
    auto definition = app::load_session_definition(argv[1], error);
    if (!definition)
      throw std::runtime_error(error);
    app::SimSession session(definition->mode.value_or(CpuMode::HD6309));
    if (!session.load_hardware_config(definition->config_path) ||
        !session.load_rom(definition->rom_path, definition->rom_format, definition->raw_base) ||
        !session.attach_cf_image(definition->cf_path, definition->cf_sectors))
      throw std::runtime_error("cannot load session resources");
    if (session.simulator().clock().frequency_hz() != 3000000 ||
        definition->gui.true_clock_hz != 3000000)
      throw std::runtime_error("CPU model and GUI pacing must both select 3 MHz");
    session.reset();
    for (unsigned batch = 0; batch < 10000; ++batch) {
      session.run_realtime_cycles(20000);
      const auto &bytes = session.serial_tx();
      std::string output(bytes.begin(), bytes.end());
      if (output.find("/ > ") != std::string::npos) {
        std::cout << "GUI session/realtime boot PASS: CPU model=3 MHz, pacing=3 MHz\n"
                  << output << '\n';
        return 0;
      }
    }
    throw std::runtime_error("no prompt within 200 million cycles");
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
