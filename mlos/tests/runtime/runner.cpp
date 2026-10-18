#include "microlind/app/hardware_config.hpp"
#include "microlind/app/image_loader.hpp"
#include "microlind/app/sim_builder.hpp"
#include "microlind/devices/compact_flash.hpp"
#include "microlind/devices/memory_mapper.hpp"
#include "microlind/devices/serial.hpp"
#include "target_runtime.hpp"
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
using namespace microlind;
using namespace target;
void check(bool ok, const std::string &why) {
  if (!ok)
    throw std::runtime_error(why);
}
struct Machine {
  devices::XR88C92 *serial{};
  devices::CompactFlash *second{}, *first{};
  std::string output, logs;
  std::shared_ptr<devices::MapperState> mapper;
  Simulator sim;
  bool micro;
  Machine(const cli::LoadedImage &rom, const cli::HardwareConfig &cfg, bool m)
      : sim(cli::build_sim(
            CpuMode::HD6309, &rom, &cfg, &serial,
            [this](uint8_t b) {
              check(output.size() < 8192, "serial bound");
              output += char(b);
            },
            &mapper, &first, nullptr, nullptr, nullptr, &second)),
        micro(m) {
    if (serial)
      serial->set_tx_b_callback([this](uint8_t b) {
        check(logs.size() < 8192, "log bound");
        logs += char(b);
      });
    sim.bus().set_access_logging(false);
    sim.bus().set_detailed_bus_phases(false);
    sim.reset_from_vector();
  }
  void step() {
    if (micro) {
      do {
        sim.tick_microcycle();
      } while (sim.has_pending_microcycles());
    } else
      sim.tick();
  }
  template <class F>
  void until(F predicate, const std::string &why, unsigned limit = 2000000) {
    for (unsigned i = 0; i < limit; i++) {
      if (predicate())
        return;
      step();
    }
    throw std::runtime_error(
        why + " PC=" + std::to_string(sim.cpu().regs().pc) +
        " panic=" + std::to_string(sim.bus().peek8(PANIC_REASON)) +
        " pid=" + std::to_string(word(CURRENT_PID)));
  }
  uint16_t word(uint16_t a) {
    return (sim.bus().peek8(a) << 8) | sim.bus().peek8(a + 1);
  }
  void word(uint16_t a, uint16_t v) {
    sim.bus().write8(a, v >> 8);
    sim.bus().write8(a + 1, v);
  }
  void bytes(uint16_t a, const std::string &s) {
    for (unsigned i = 0; i < s.size(); i++)
      sim.bus().write8(a + i, uint8_t(s[i]));
  }
  void ready(unsigned pid = 1) {
    until(
        [&] {
          return word(CURRENT_PID) == pid && !sim.bus().privileged() &&
                 sim.bus().peek8(ENTRY_DEPTH) == 0 &&
                 sim.cpu().regs().pc < 0xC000;
        },
        "application safe point");
  }
  void begin(unsigned pid, uint8_t call, uint16_t params = 0x100) {
    ready(pid);
    auto &r = sim.cpu().regs();
    sim.bus().write8(0x2000, 0x3F);
    sim.bus().write8(0x2001, 0x20);
    sim.bus().write8(0x2002, 0xFE);
    r.pc = 0x2000;
    r.a = call;
    r.x = params;
    r.s = 0x3F80;
    r.cc = 0x40;
    r.y = 0x1357;
    r.u = 0x2468;
    r.v = 0xABCD;
    r.e = 0x67;
    r.f = 0x89;
    r.dp = 0x12;
  }
  uint16_t finish(unsigned pid) {
    until(
        [&] {
          return word(CURRENT_PID) == pid && !sim.bus().privileged() &&
                 !sim.bus().peek8(ENTRY_DEPTH) && sim.cpu().regs().pc == 0x2001;
        },
        "syscall resume");
    auto &r = sim.cpu().regs();
    check(r.y == 0x1357 && r.u == 0x2468 && r.v == 0xABCD && r.e == 0x67 &&
              r.f == 0x89 && r.dp == 0x12 && r.s == 0x3F80,
          "native context across scheduler");
    return (r.a << 8) | r.b;
  }
  uint16_t call(uint8_t n, unsigned pid = 1, uint16_t p = 0x100) {
    begin(pid, n, p);
    return finish(pid);
  }
  bool error() { return sim.cpu().regs().cc & 1; }
  void boot() {
    until(
        [&] {
          return output.find("MLOS CF scheduler\r\n") != std::string::npos;
        },
        "CF kernel/init bootstrap");
    ready();
  }
  unsigned free() { return sim.bus().peek8(FREE_COUNT); }
};
void profile(Machine &m) {
  m.begin(1, SYS_GETPID);
  m.sim.cpu().regs().cc |= 0x10;
  auto start = m.sim.clock().total_cycles();
  check(m.finish(1) == 1, "profile getpid");
  std::cout << "runtime getpid cycles=" << m.sim.clock().total_cycles() - start
            << "\n";
  m.begin(1, SYS_YIELD);
  m.sim.cpu().regs().cc |= 0x10;
  m.sim.bus().write8(SCHED_PHASE, 4);
  start = m.sim.clock().total_cycles();
  m.until(
      [&] {
        return m.word(CURRENT_PID) == 2 && !m.sim.bus().privileged() &&
               !m.sim.bus().peek8(ENTRY_DEPTH) &&
               m.sim.cpu().regs().pc < 0xC000;
      },
      "profile switch");
  std::cout << "runtime yield/context switch cycles="
            << m.sim.clock().total_cycles() - start << "\n";
  m.finish(1);
}
void guards(Machine &m) {
  check(m.word(KERNEL_CANARY) == 0xA55A && m.word(EMERGENCY_CANARY) == 0xA55A,
        "runtime common stack guards");
  unsigned low = KERNEL_STACK;
  for (unsigned a = KERNEL_CANARY + 2; a < KERNEL_STACK; a++)
    if (m.sim.bus().peek8(a) != 0xCD) {
      low = a;
      break;
    }
  std::cout << "observed common stack modified span=" << KERNEL_STACK - low
            << "/" << KERNEL_STACK - KERNEL_CANARY - 2 << "\n";
}
void scheduling(Machine &m) {
  m.bytes(0x300, std::string("worker.mlx\0", 11));
  m.word(0x100, 0x300);
  m.word(0x102, 0x0200);
  m.word(0x104, 0);
  m.word(0x106, 0);
  auto child = m.call(SYS_SPAWN);
  check(child == 3 && !m.error(), "background class child");
  auto start = m.word(TICKS + 2);
  unsigned counts[3]{};
  while (uint16_t(m.word(TICKS + 2) - start) < 210) {
    auto p = m.word(CURRENT_PID);
    if (p >= 1 && p <= 3 && !m.sim.bus().privileged() &&
        !m.sim.bus().peek8(ENTRY_DEPTH))
      counts[p - 1]++;
    m.step();
  }
  check(counts[2] > 100 && counts[0] > counts[1] && counts[1] > counts[2],
        "non-yielding 4:2:1 classes all progress");
  m.ready(1);
  m.word(0x100, child);
  check(m.call(SYS_KILL) == 0 && !m.error(), "terminate background child");
  check(m.call(SYS_WAIT) == 130 && !m.error(), "reap background child");
  std::cout << "scheduler application samples=" << counts[0] << "," << counts[1]
            << "," << counts[2] << " ticks=210\n";
}
void memory(Machine &m) {
  check(m.call(SYS_GETPID) == 1 && !m.error(), "getpid");
  auto initial = m.free();
  m.word(0x100, 20000);
  auto pointer = m.call(SYS_HEAP_ALLOC);
  check(pointer == 0x4000 && !m.error(), "spanning heap allocation");
  check(m.free() == initial - 2, "whole-bank admission");
  m.word(0x7FFF, 0x4567);
  m.call(SYS_YIELD);
  check(m.word(0x7FFF) == 0x4567, "spanning pointers across dispatch");
  m.word(0x100, pointer);
  check(m.call(SYS_HEAP_FREE) == 0 && !m.error(), "heap free");
  check(m.free() == initial && m.mapper->bank[1] == 2 && m.mapper->bank[2] == 2,
        "empty heap frames reclaimed");
  m.word(0x100, 0x3000);
  check(m.call(SYS_HEAP_FREE) == uint16_t(SYS_EINVAL) && m.error(),
        "invalid heap free");
}
void ipc(Machine &m) {
  auto baseline = m.free();
  m.word(0x100, 1);
  m.word(0x102, 37);
  m.sim.bus().write8(0x104, 1);
  m.sim.bus().write8(0x105, 0);
  m.word(0x106, 0x180);
  auto tx = m.call(SYS_CHANNEL_CREATE);
  check(!m.error(), "channel create");
  auto rx = m.word(0x180);
  m.bytes(0x300, std::string(31, 'Q'));
  m.word(0x100, tx);
  m.word(0x102, 0x300);
  m.word(0x104, 31);
  m.word(0x106, 0);
  m.word(0x108, 0);
  check(m.call(SYS_SEND) == 31 && !m.error(), "atomic message send");
  m.word(0x100, rx);
  m.word(0x102, 0x4000);
  m.word(0x104, 5);
  m.word(0x108, 0x180);
  check(m.call(SYS_RECEIVE) == uint16_t(SYS_EMSGSIZE) && m.error(),
        "short message buffer");
  check(m.word(0x180) == 31, "required message length retained");
  m.word(0x102, 0x500);
  m.word(0x104, 31);
  check(m.call(SYS_RECEIVE) == 31 && !m.error(), "message receive");
  check(m.sim.bus().peek8(0x500) == 'Q' && m.sim.bus().peek8(0x51E) == 'Q',
        "message bytes");
  for (unsigned i = 0; i < 20; i++) {
    m.word(0x100, tx);
    m.word(0x102, 0x300);
    m.word(0x104, 31);
    m.word(0x108, 0);
    check(m.call(SYS_SEND) == 31 && !m.error(), "ring wrap send");
    m.word(0x100, rx);
    m.word(0x102, 0x500);
    check(m.call(SYS_RECEIVE) == 31 && !m.error(), "ring wrap receive");
  }
  m.word(0x100, tx);
  m.word(0x102, 0x300);
  check(m.call(SYS_SEND) == 31 && !m.error(), "drain message");
  m.word(0x100, tx);
  check(m.call(SYS_CLOSE) == 0 && !m.error(), "producer close");
  m.word(0x100, rx);
  m.word(0x102, 0x500);
  m.word(0x104, 31);
  check(m.call(SYS_RECEIVE) == 31 && !m.error(), "producer-death drain");
  check(m.free() == baseline, "drained payload reclaimed");
  check(m.call(SYS_RECEIVE) == 0 && !m.error(), "EOF after drain");
  check(m.call(SYS_CLOSE) == 0 && !m.error(), "consumer close");
  // A real waiter sleeps in PID1, PID2 publishes, then PID1 resumes with
  // readiness.
  m.ready(2);
  m.word(0x100, 1);
  m.word(0x102, 53);
  m.word(0x104, 0);
  m.word(0x106, 0x180);
  tx = m.call(SYS_CHANNEL_CREATE, 2);
  check(!m.error(), "cross-process stream");
  rx = m.word(0x180);
  m.ready(1);
  m.word(0x180, rx);
  m.word(0x100, 0x180);
  m.word(0x102, 0x0100);
  m.word(0x104, 0);
  m.word(0x106, 0);
  m.begin(1, SYS_WAIT_ANY);
  m.until([&] { return m.sim.bus().peek8(PROC_TABLE + P_STATE) == PS_WAIT; },
          "waiter blocks");
  m.ready(2);
  m.bytes(0x300, "hello");
  m.word(0x100, tx);
  m.word(0x102, 0x300);
  m.word(0x104, 5);
  m.word(0x106, 0);
  m.word(0x108, 0);
  check(m.call(SYS_SEND, 2) == 5 && !m.error(),
        "producer progresses while peer waits");
  check(m.finish(1) == 1 && !m.error(), "no lost wakeup");
  m.word(0x100, rx);
  m.call(SYS_CLOSE);
  m.ready(2);
  m.word(0x100, tx);
  check(m.call(SYS_SEND, 2) == uint16_t(SYS_EPIPE) && m.error(),
        "consumer death wakes writer");
  m.call(SYS_CLOSE, 2);
  m.ready(1);
  check(m.free() == baseline, "stream teardown accounting");
}
void ipc_spans(Machine &m) {
  const auto baseline = m.free();
  std::string bytes;
  for (unsigned i = 0; i < 512; ++i) bytes += char((i * 37 + 11) & 255);
  for (unsigned capacity : {263, 511}) {
    m.word(0x100, 1); m.word(0x102, capacity);
    m.word(0x104, 0); m.word(0x106, 0x180);
    auto tx = m.call(SYS_CHANNEL_CREATE), rx = m.word(0x180);
    check(!m.error(), "binary stream creation");
    for (unsigned count : {257, 1, 256, 263, 2, 255, 129}) {
      m.bytes(0x1000, bytes.substr(0, count));
      m.word(0x100, tx); m.word(0x102, 0x1000);
      m.word(0x104, count); m.word(0x106, 0); m.word(0x108, 0);
      check(m.call(SYS_SEND) == count && !m.error(), "split-span stream send");
      m.bytes(0x1200, std::string(count, '?'));
      m.word(0x100, rx); m.word(0x102, 0x1200);
      check(m.call(SYS_RECEIVE) == count && !m.error(), "split-span stream receive");
      for (unsigned j = 0; j < count; ++j)
        check(m.sim.bus().peek8(0x1200+j) == uint8_t(bytes[j]), "binary wrap bytes");
    }
    for (auto h : {tx, rx}) { m.word(0x100, h); m.call(SYS_CLOSE); }
    check(m.free() == baseline, "split-span stream frame accounting");
  }
}
void idle_wait_deadline(Machine &m) {
  m.word(0x100, 1); m.word(0x102, 37);
  m.word(0x104, 0); m.word(0x106, 0x180);
  auto tx = m.call(SYS_CHANNEL_CREATE), rx = m.word(0x180);
  check(!m.error(), "deadline test channel");
  const uint32_t deadline = (uint32_t(m.word(TICKS)) << 16 | m.word(TICKS+2)) + 20;
  m.word(0x180, rx); m.word(0x100, 0x180); m.word(0x102, 0x0100);
  m.word(0x104, deadline >> 16); m.word(0x106, deadline);
  check(m.call(SYS_WAIT_ANY) == uint16_t(SYS_ETIMEDOUT) && m.error(),
        "wait deadline expires without an IPC mutation");
  for (auto h : {tx, rx}) { m.word(0x100, h); m.call(SYS_CLOSE); }
}
void loading_boundaries(Machine &m) {
  const auto baseline = m.free();
  m.bytes(0x300, std::string("boundary.mlx") + char(0));
  m.word(0x100, 0x300); m.word(0x102, 0x0100);
  m.word(0x104, 0); m.word(0x106, 0);
  auto pid = m.call(SYS_SPAWN);
  check(!m.error(), "three-window image admitted");
  m.ready(pid);
  for (unsigned i = 0; i < 16; ++i)
    check(m.sim.bus().peek8(0x3FE0+i) == i, "image data before BSS boundary");
  for (unsigned i = 0; i < 32; ++i)
    check(m.sim.bus().peek8(0x3FF0+i) == 0, "zero across window boundary");
  for (unsigned i = 0; i < 64; ++i)
    check(m.sim.bus().peek8(0x7FE0+i) == i+64, "data across window boundary");
  m.ready(1); m.word(0x100, pid);
  check(m.call(SYS_KILL) == 0 && !m.error(), "boundary child cleanup");
  check(m.call(SYS_WAIT) == 130 && !m.error(), "boundary child reap");
  check(m.free() == baseline, "boundary child frames reclaimed");
}
void services(Machine &m) {
  m.bytes(0x300, std::string("echo\0", 5));
  m.word(0x100, 0x300);
  auto listener = m.call(SYS_LISTEN);
  check(!m.error(), "listen");
  m.ready(2);
  m.bytes(0x300, std::string("echo\0", 5));
  m.word(0x100, 0x300);
  m.word(0x102, 0x180);
  m.word(0x104, 53);
  m.word(0x106, 0);
  check(m.call(SYS_CONNECT, 2) == 0 && !m.error(), "connect");
  auto client_tx = m.word(0x180), client_rx = m.word(0x182);
  m.ready(1);
  m.word(0x100, listener);
  m.word(0x102, 0x180);
  check(m.call(SYS_ACCEPT) == 0 && !m.error(), "accept");
  auto server_tx = m.word(0x180), server_rx = m.word(0x182);
  m.ready(2);
  m.bytes(0x300, "ping");
  m.word(0x100, client_tx);
  m.word(0x102, 0x300);
  m.word(0x104, 4);
  m.word(0x106, 0);
  m.word(0x108, 0);
  check(m.call(SYS_SEND, 2) == 4 && !m.error(), "client send");
  m.ready(1);
  m.word(0x100, server_rx);
  m.word(0x102, 0x500);
  m.word(0x104, 4);
  m.word(0x106, 0);
  m.word(0x108, 0);
  check(m.call(SYS_RECEIVE) == 4 && !m.error(), "service receive");
  check(m.word(0x500) == 0x7069, "service data");
  for (auto handle : {listener, server_tx, server_rx}) {
    m.word(0x100, handle);
    check(m.call(SYS_CLOSE) == 0 && !m.error(), "service endpoint close");
  }
  m.ready(2);
  for (auto handle : {client_tx, client_rx}) {
    m.word(0x100, handle);
    m.call(SYS_CLOSE, 2);
  }
  m.ready(1);
}
void loading_failures(Machine &m) {
  auto baseline = m.free();
  for (auto name : {"bad-layout.mlx", "bad-checksum.mlx"}) {
    m.bytes(0x300, std::string(name) + char(0));
    m.word(0x100, 0x300);
    m.word(0x102, 0x0100);
    m.word(0x104, 0);
    m.word(0x106, 0);
    check(m.call(SYS_SPAWN) == uint16_t(SYS_EINVAL) && m.error(),
          "malformed image does not publish");
    check(!m.sim.bus().peek8(LOADER_ACTIVE) && m.free() == baseline,
          "failed loading restores frames and transaction");
  }
  std::vector<uint16_t> held;
  while (m.free()) {
    held.push_back(m.call(SYS_BANK_ALLOC));
    check(!m.error(), "exhaustion setup");
  }
  m.bytes(0x300, std::string("worker.mlx\0", 11));
  m.word(0x100, 0x300);
  m.word(0x102, 0x0100);
  m.word(0x104, 0);
  m.word(0x106, 0);
  check(m.call(SYS_SPAWN) == uint16_t(SYS_ENOMEM) && m.error(),
        "spawn allocation admission failure");
  check(m.free() == 0 && !m.sim.bus().peek8(LOADER_ACTIVE),
        "no partial spawn on exhaustion");
  for (auto h : held) {
    m.word(0x100, h);
    check(m.call(SYS_BANK_FREE) == 0 && !m.error(), "restore exhausted banks");
  }
  check(m.free() == baseline, "exhaustion restores accounting");
}
void trap_cleanup(Machine &m) {
  auto baseline = m.free();
  m.ready(2);
  m.sim.bus().write8(0x2000, 0x10);
  m.sim.bus().write8(0x2001, 0x3F);
  m.sim.cpu().regs().pc = 0x2000;
  m.until(
      [&] {
        return m.sim.bus().peek8(PROC_TABLE + PROC_SIZE + P_STATE) == PS_ZOMBIE;
      },
      "application trap cleanup");
  m.ready(1);
  m.word(0x100, 2);
  check(m.call(SYS_WAIT) == 128 && !m.error(), "parent reaps trapped child");
  check(m.free() == baseline + 1, "trapped resident reclaimed");
  check(m.call(SYS_GETPID) == 1 && !m.error(), "survivor continues after trap");
}
void modules(Machine &m) {
  auto baseline = m.free();
  m.bytes(0x300, std::string("broken.mld\0", 11));
  m.word(0x100, 0x300);
  check(m.call(SYS_MODULE_LOAD) == uint16_t(SYS_EINVAL) && m.error(),
        "module checksum rejection");
  check(m.free() == baseline && !m.sim.bus().peek8(LOADER_ACTIVE),
        "bad module never publishes and restores provisional code frame");
  m.bytes(0x300, std::string("delay.mld\0", 10));
  m.word(0x100, 0x300);
  auto id = m.call(SYS_MODULE_LOAD);
  check(id == 1 && !m.error(), "validated permanent module load");
  check(m.free() == baseline - 1, "module code charged until reset");
  m.word(0x100, id);
  m.word(0x102, 0x0200);
  m.word(0x104, 7);
  check(m.call(SYS_MODULE_BIND) == 0 && !m.error(),
        "first instance private state bind");
  auto bound = m.free();
  m.word(0x102, 0x0300);
  m.word(0x104, 0xFFFF);
  check(m.call(SYS_MODULE_BIND) == uint16_t(SYS_EINVAL) && m.error(),
        "second bind callback failure");
  check(m.free() == bound, "failed second bind rolls back state");
  m.word(0x104, 19);
  check(m.call(SYS_MODULE_BIND) == 0 && !m.error(),
        "shared code second instance");
  check(m.free() == bound - 1, "separate charged instance state");
}
void drivers(Machine &m) {
  m.word(0x100, 0);
  auto dev = m.call(SYS_DEVICE_CLAIM);
  check(!m.error(), "exclusive CF claim");
  m.ready(2);
  m.word(0x100, 0);
  check(m.call(SYS_DEVICE_CLAIM, 2) == uint16_t(SYS_EBUSY) && m.error(),
        "raw owner exclusivity");
  m.ready(1);
  m.word(0x100, dev);
  m.word(0x102, 0);
  m.word(0x104, 0);
  m.word(0x106, 0);
  m.word(0x108, 0);
  m.word(0x10A, 512);
  auto request = m.call(SYS_IO_SUBMIT);
  check(!m.error(), "CF async read admission");
  m.word(0x100, dev);
  check(m.call(SYS_CLOSE) == uint16_t(SYS_EBUSY) && m.error(),
        "live request holds device claim");
  m.word(0x180, request);
  m.word(0x100, 0x180);
  m.word(0x102, 0x0100);
  m.word(0x104, 0);
  m.word(0x106, 0);
  check(m.call(SYS_WAIT_ANY) == 1 && !m.error(), "wait for CF completion");
  m.word(0x100, request);
  m.word(0x102, 0x2100);
  check(m.call(SYS_IO_COLLECT) == 512 && !m.error(), "collect512-byte read");
  check(m.word(0x2100) == 0x4D4C && m.word(0x2102) == 0x5054,
        "read actual MLPT via async driver");
  m.word(0x100, dev);
  check(m.call(SYS_CLOSE) == 0 && !m.error(),
        "claim released after quiescence");
  m.word(0x100, 2 << 8);
  auto a = m.call(SYS_DEVICE_CLAIM);
  check(!m.error(), "mock instance A");
  m.word(0x100, 3 << 8);
  auto b = m.call(SYS_DEVICE_CLAIM);
  check(!m.error(), "mock instance B");
  m.word(0x100, a);
  m.word(0x102, 0x0100);
  m.word(0x104, 0);
  m.word(0x106, 0);
  m.word(0x108, 0x2100);
  m.word(0x10A, 512);
  auto ra = m.call(SYS_IO_SUBMIT);
  check(!m.error(), "first pending controller");
  m.word(0x100, b);
  auto rb = m.call(SYS_IO_SUBMIT);
  check(!m.error(), "second pending controller");
  m.word(0x100, rb);
  check(m.call(SYS_IO_CANCEL) == 0 && !m.error(),
        "cancel accepted without early reuse");
  m.word(0x180, ra);
  m.word(0x100, 0x180);
  m.word(0x102, 0x0100);
  m.word(0x104, 0);
  m.word(0x106, 0);
  m.call(SYS_WAIT_ANY);
  m.word(0x100, ra);
  m.word(0x102, 0);
  check(m.call(SYS_IO_COLLECT) == 512 && !m.error(),
        "healthy controller completes independently");
  m.word(0x180, rb);
  m.word(0x100, 0x180);
  m.word(0x102, 0x0100);
  m.word(0x104, 0);
  m.word(0x106, 0);
  m.call(SYS_WAIT_ANY);
  m.word(0x100, rb);
  check(m.call(SYS_IO_COLLECT) == uint16_t(SYS_ECANCELLED) && m.error(),
        "cancel settles before collection");
  for (auto h : {a, b}) {
    m.word(0x100, h);
    check(m.call(SYS_CLOSE) == 0 && !m.error(),
          "independent instance teardown");
  }
}
void timeout_quarantine(Machine &m) {
  m.ready(1);
  m.word(0x100, 0);
  auto device = m.call(SYS_DEVICE_CLAIM);
  check(!m.error(), "timeout fixture device");
  m.first->set_command_delay_cycles(30000000);
  m.word(0x100, device);
  m.word(0x102, 0);
  m.word(0x104, 0);
  m.word(0x106, 0);
  m.word(0x108, 0);
  m.word(0x10A, 512);
  auto request = m.call(SYS_IO_SUBMIT);
  check(!m.error(), "timeout request admitted");
  m.word(0x180, request);
  m.word(0x100, 0x180);
  m.word(0x102, 0x0100);
  m.word(0x104, 0);
  m.word(0x106, 0);
  m.call(SYS_WAIT_ANY);
  m.word(0x100, request);
  m.word(0x102, 0x2100);
  check(m.call(SYS_IO_COLLECT) == uint16_t(SYS_EIO) && m.error(),
        "timed-out PIO completion");
  m.word(0x100, device);
  check(m.call(SYS_CLOSE) == uint16_t(SYS_EIO) && m.error(),
        "unsafe controller quiescence quarantines ownership");
  m.word(0x100, 0);
  check(m.call(SYS_DEVICE_CLAIM) == uint16_t(SYS_EBUSY) && m.error(),
        "no replacement raw owner before reset");
}
void backplanes(Machine &m) {
  // Exercise privileged adapters with RAM-backed mock registers before init
  // starts the timer. No unassigned physical backplane address is probed.
  m.until([&] { return m.sim.cpu().regs().pc == runtime_init; },
          "validated core entry for backplane adapter");
  auto invoke = [&](uint16_t entry, uint8_t a = 0, uint8_t b = 0) {
    auto &r = m.sim.cpu().regs();
    check(m.sim.bus().privileged(), "trusted backplane call");
    r.pc = entry;
    r.s = 0xCBFE;
    r.cc = 0x50;
    r.dp = 0;
    r.a = a;
    r.b = b;
    m.word(0xCBFE, 0xC5F0);
    m.until([&] { return r.pc == 0xC5F0; }, "backplane adapter return", 10000);
    check(r.s == 0xCC00, "bounded backplane adapter stack");
    return uint16_t((r.a << 8) | r.b);
  };
  invoke(backplane_init);
  check(invoke(backplane_pending) == uint16_t(SYS_ENODEV) && m.error(),
        "unassigned controller disabled");
  check(invoke(backplane_set_mask, 0xFF, 2) == uint16_t(SYS_ENODEV) && m.error(),
        "out of range controller rejected");
  for (unsigned i = 0; i < 2; ++i) {
    m.word(backplane_bindings + i * BACKPLANE_SIZE + BP_PENDING, 0xDE20 + 2*i);
    m.word(backplane_bindings + i * BACKPLANE_SIZE + BP_MASK, 0xDE21 + 2*i);
    m.sim.bus().write8(0xDE20 + 2*i, 0xFF);
    m.sim.bus().write8(0xDE21 + 2*i, 0xFF);
  }
  invoke(backplane_init);
  check(m.sim.bus().peek8(0xDE21) == 0 && m.sim.bus().peek8(0xDE23) == 0,
        "configured backplanes start reset-disabled");
  check(invoke(backplane_set_mask, 0xC5, 0) == 0 && !m.error(),
        "normalized first mask");
  check(invoke(backplane_pending) == 5 && !m.error() &&
            m.sim.bus().peek8(0xDE20) == 0xFF && m.sim.bus().peek8(0xDE21) == 5,
        "pending non-clearing and reserved bits masked");
  check(invoke(backplane_pending, 0, 1) == 0 && !m.error(),
        "second controller independent");
  invoke(backplane_set_mask, 0xC2, 1);
  check(invoke(backplane_pending, 0, 1) == 2 && !m.error(),
        "second normalized pending");
  check(invoke(backplane_pending) == 5 && !m.error(),
        "first mask remains unchanged");
  m.sim.bus().write8(BACKPLANE_TABLE + BP_VERSION, 2);
  check(invoke(backplane_pending) == uint16_t(SYS_ENODEV) && m.error(),
        "unrecognized controller contract rejected");
}
int main(int argc, char **argv) {
  try {
    check(argc == 3, "runtime runner ROM/config");
    std::string error;
    auto cfg = cli::load_hardware_config(argv[2], error);
    auto rom = cli::load_image(argv[1], cli::RomFormat::Ihex);
    check(bool(cfg) && bool(rom), error);
    for (bool micro : {false, true}) {
      {
        Machine adapter(*rom, *cfg, micro);
        backplanes(adapter);
      }
      Machine m(*rom, *cfg, micro);
      m.boot();
      profile(m);
      scheduling(m);
      memory(m);
      ipc(m);
      ipc_spans(m);
      idle_wait_deadline(m);
      services(m);
      loading_boundaries(m);
      loading_failures(m);
      modules(m);
      drivers(m);
      trap_cleanup(m);
      timeout_quarantine(m);
      guards(m);
      std::cout << (micro ? "microcycle" : "instruction")
                << ": CF/loader/preemption/heap/IPC/services/requests PASS\n";
    }
    return 0;
  } catch (std::exception &e) {
    std::cerr << "runtime FAIL: " << e.what() << '\n';
    return 1;
  }
}
