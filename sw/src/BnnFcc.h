#pragma once

#include <cstdint>

#include "App.h"

struct BnnFccBeat {
    std::uint64_t data;
    std::uint8_t keep;
    std::uint8_t last;
};

class BnnFcc : public App {
public:
    explicit BnnFcc(Board& board);

    void reset();
    void clearOutput();
    void clearErrors();
    void clearCycleCount();

    std::uint32_t status() const;
    std::uint32_t cycleCount() const;
    bool isBusy() const;
    bool hasOutput() const;

    bool waitIdle(std::uint32_t timeout_iters) const;
    bool sendConfig(const BnnFccBeat* beats, unsigned count, std::uint32_t timeout_iters);
    bool sendImage(const std::uint8_t* pixels, unsigned count, std::uint32_t timeout_iters);
    bool waitForOutput(std::uint32_t* result, std::uint32_t timeout_iters);
    bool runImage(const std::uint8_t* pixels,
                  unsigned count,
                  std::uint32_t* result,
                  std::uint32_t timeout_iters);

private:
    static constexpr std::uint32_t REG_CONTROL = 0x00;
    static constexpr std::uint32_t REG_STATUS = 0x04;
    static constexpr std::uint32_t REG_CFG_DATA_LO = 0x08;
    static constexpr std::uint32_t REG_CFG_DATA_HI = 0x0c;
    static constexpr std::uint32_t REG_CFG_META = 0x10;
    static constexpr std::uint32_t REG_IMG_DATA_LO = 0x14;
    static constexpr std::uint32_t REG_IMG_DATA_HI = 0x18;
    static constexpr std::uint32_t REG_IMG_META = 0x1c;
    static constexpr std::uint32_t REG_OUT_DATA = 0x20;
    static constexpr std::uint32_t REG_OUT_CTRL = 0x24;
    static constexpr std::uint32_t REG_CYCLE_COUNT = 0x28;

    static constexpr std::uint32_t CONTROL_RESET = 1u << 0;
    static constexpr std::uint32_t CONTROL_CLEAR_OUTPUT = 1u << 1;
    static constexpr std::uint32_t CONTROL_CLEAR_ERRORS = 1u << 2;
    static constexpr std::uint32_t CONTROL_CLEAR_CYCLES = 1u << 3;

    static constexpr std::uint32_t STATUS_CFG_FULL = 1u << 0;
    static constexpr std::uint32_t STATUS_IMG_FULL = 1u << 1;
    static constexpr std::uint32_t STATUS_OUT_VALID = 1u << 2;
    static constexpr std::uint32_t STATUS_BUSY = 1u << 3;
    static constexpr std::uint32_t STATUS_ERROR_MASK = (1u << 6) | (1u << 7);

    static constexpr std::uint32_t META_LAST = 1u << 8;
    static constexpr std::uint32_t META_PUSH = 1u << 16;

    static constexpr std::uint32_t OUT_CTRL_POP = 1u << 0;
    static constexpr std::uint32_t OUT_CTRL_CLEAR = 1u << 1;

    bool waitStatusClear(std::uint32_t mask, std::uint32_t timeout_iters) const;
    bool pushConfigBeat(const BnnFccBeat& beat, std::uint32_t timeout_iters);
    bool pushImageBeat(std::uint64_t data,
                       std::uint8_t keep,
                       bool last,
                       std::uint32_t timeout_iters);
};
