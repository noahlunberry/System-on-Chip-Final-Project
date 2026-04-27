#pragma once

#include <cstdint>

#include "Board.h"

class App {
public:
    explicit App(Board& board);

protected:
    std::uint32_t readReg(std::uint32_t offset) const;
    void writeReg(std::uint32_t offset, std::uint32_t value) const;

private:
    Board& board_;
};
