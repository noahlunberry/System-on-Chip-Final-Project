#pragma once

#include <cstdint>

class Board {
public:
    explicit Board(std::uintptr_t base_address);

    std::uint32_t read(std::uint32_t offset) const;
    void write(std::uint32_t offset, std::uint32_t value) const;

private:
    std::uintptr_t base_address_;
};
