#include "BnnFcc.h"

BnnFcc::BnnFcc(Board& board) : App(board) {}

void BnnFcc::reset() {
    writeReg(REG_CONTROL, CONTROL_RESET | CONTROL_CLEAR_OUTPUT |
                          CONTROL_CLEAR_ERRORS | CONTROL_CLEAR_CYCLES);
}

void BnnFcc::clearOutput() {
    writeReg(REG_OUT_CTRL, OUT_CTRL_CLEAR);
}

void BnnFcc::clearErrors() {
    writeReg(REG_CONTROL, CONTROL_CLEAR_ERRORS);
}

void BnnFcc::clearCycleCount() {
    writeReg(REG_CONTROL, CONTROL_CLEAR_CYCLES);
}

std::uint32_t BnnFcc::status() const {
    return readReg(REG_STATUS);
}

std::uint32_t BnnFcc::cycleCount() const {
    return readReg(REG_CYCLE_COUNT);
}

bool BnnFcc::isBusy() const {
    return (status() & STATUS_BUSY) != 0;
}

bool BnnFcc::hasOutput() const {
    return (status() & STATUS_OUT_VALID) != 0;
}

bool BnnFcc::waitStatusClear(std::uint32_t mask, std::uint32_t timeout_iters) const {
    while ((status() & mask) != 0) {
        if (timeout_iters == 0) {
            return false;
        }
        --timeout_iters;
    }
    return true;
}

bool BnnFcc::waitIdle(std::uint32_t timeout_iters) const {
    return waitStatusClear(STATUS_BUSY, timeout_iters);
}

bool BnnFcc::pushConfigBeat(const BnnFccBeat& beat, std::uint32_t timeout_iters) {
    if (!waitStatusClear(STATUS_CFG_FULL, timeout_iters)) {
        return false;
    }

    writeReg(REG_CFG_DATA_LO, static_cast<std::uint32_t>(beat.data));
    writeReg(REG_CFG_DATA_HI, static_cast<std::uint32_t>(beat.data >> 32));
    writeReg(REG_CFG_META,
             static_cast<std::uint32_t>(beat.keep) |
             (beat.last ? META_LAST : 0u) |
             META_PUSH);

    return (status() & STATUS_ERROR_MASK) == 0;
}

bool BnnFcc::pushImageBeat(std::uint64_t data,
                           std::uint8_t keep,
                           bool last,
                           std::uint32_t timeout_iters) {
    if (!waitStatusClear(STATUS_IMG_FULL, timeout_iters)) {
        return false;
    }

    writeReg(REG_IMG_DATA_LO, static_cast<std::uint32_t>(data));
    writeReg(REG_IMG_DATA_HI, static_cast<std::uint32_t>(data >> 32));
    writeReg(REG_IMG_META,
             static_cast<std::uint32_t>(keep) |
             (last ? META_LAST : 0u) |
             META_PUSH);

    return (status() & STATUS_ERROR_MASK) == 0;
}

bool BnnFcc::sendConfig(const BnnFccBeat* beats,
                        unsigned count,
                        std::uint32_t timeout_iters) {
    for (unsigned i = 0; i < count; ++i) {
        if (!pushConfigBeat(beats[i], timeout_iters)) {
            return false;
        }
    }
    return true;
}

bool BnnFcc::sendImage(const std::uint8_t* pixels,
                       unsigned count,
                       std::uint32_t timeout_iters) {
    for (unsigned offset = 0; offset < count; offset += 8) {
        std::uint64_t data = 0;
        std::uint8_t keep = 0;

        for (unsigned lane = 0; lane < 8; ++lane) {
            const unsigned index = offset + lane;
            if (index < count) {
                data |= static_cast<std::uint64_t>(pixels[index]) << (8 * lane);
                keep |= static_cast<std::uint8_t>(1u << lane);
            }
        }

        const bool last = (offset + 8) >= count;
        if (!pushImageBeat(data, keep, last, timeout_iters)) {
            return false;
        }
    }
    return true;
}

bool BnnFcc::waitForOutput(std::uint32_t* result, std::uint32_t timeout_iters) {
    while (!hasOutput()) {
        if (timeout_iters == 0) {
            return false;
        }
        --timeout_iters;
    }

    if (result != nullptr) {
        *result = readReg(REG_OUT_DATA);
    }
    writeReg(REG_OUT_CTRL, OUT_CTRL_POP);
    return true;
}

bool BnnFcc::runImage(const std::uint8_t* pixels,
                      unsigned count,
                      std::uint32_t* result,
                      std::uint32_t timeout_iters) {
    if (!sendImage(pixels, count, timeout_iters)) {
        return false;
    }
    return waitForOutput(result, timeout_iters);
}
