#include "App.h"

App::App(Board& board) : board_(board) {}

std::uint32_t App::readReg(std::uint32_t offset) const {
    return board_.read(offset);
}

void App::writeReg(std::uint32_t offset, std::uint32_t value) const {
    board_.write(offset, value);
}
