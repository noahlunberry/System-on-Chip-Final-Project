#include "Board.h"

#include "xil_io.h"

Board::Board(std::uintptr_t base_address) : base_address_(base_address) {}

std::uint32_t Board::read(std::uint32_t offset) const {
    return Xil_In32(static_cast<UINTPTR>(base_address_ + offset));
}

void Board::write(std::uint32_t offset, std::uint32_t value) const {
    Xil_Out32(static_cast<UINTPTR>(base_address_ + offset), value);
}
