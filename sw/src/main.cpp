#include <cstdint>

#include "xil_printf.h"
#include "xparameters.h"
#include "xtime_l.h"

#include "BnnFcc.h"
#include "Board.h"
#include "bnn_model_data.h"
#include "bnn_test_data.h"

#ifndef BNN_FCC_BASEADDR
#if defined(XPAR_BNN_ACCEL_0_S_AXI_BASEADDR)
#define BNN_FCC_BASEADDR XPAR_BNN_ACCEL_0_S_AXI_BASEADDR
#elif defined(XPAR_BNN_ACCEL_0_BASEADDR)
#define BNN_FCC_BASEADDR XPAR_BNN_ACCEL_0_BASEADDR
#elif defined(XPAR_BNN_FCC_VIVADO_AXI_LITE_SMALL_0_S_AXI_BASEADDR)
#define BNN_FCC_BASEADDR XPAR_BNN_FCC_VIVADO_AXI_LITE_SMALL_0_S_AXI_BASEADDR
#elif defined(XPAR_BNN_FCC_VIVADO_AXI_LITE_SMALL_0_BASEADDR)
#define BNN_FCC_BASEADDR XPAR_BNN_FCC_VIVADO_AXI_LITE_SMALL_0_BASEADDR
#elif defined(XPAR_BNN_FCC_AXI_LITE_0_S_AXI_BASEADDR)
#define BNN_FCC_BASEADDR XPAR_BNN_FCC_AXI_LITE_0_S_AXI_BASEADDR
#elif defined(XPAR_BNN_FCC_AXI_LITE_0_BASEADDR)
#define BNN_FCC_BASEADDR XPAR_BNN_FCC_AXI_LITE_0_BASEADDR
#else
#error "Define BNN_FCC_BASEADDR or check the Vivado IP instance name in xparameters.h."
#endif
#endif

namespace {
constexpr std::uint32_t kPollTimeout = 100000000u;
}

int main() {
    Board board(BNN_FCC_BASEADDR);
    BnnFcc bnn(board);

    xil_printf("BNN FCC bare-metal test\r\n");

    bnn.reset();
    bnn.clearOutput();
    bnn.clearErrors();

    xil_printf("Sending %u configuration beats\r\n", bnn_data::kConfigBeatCount);
    if (!bnn.sendConfig(bnn_data::kConfigBeats, bnn_data::kConfigBeatCount, kPollTimeout)) {
        xil_printf("Configuration stream failed, status=0x%08x\r\n",
                   static_cast<unsigned>(bnn.status()));
        return 1;
    }

    if (!bnn.waitIdle(kPollTimeout)) {
        xil_printf("Timed out waiting for config drain, status=0x%08x\r\n",
                   static_cast<unsigned>(bnn.status()));
        return 1;
    }

    bnn.clearCycleCount();

    unsigned pass = 0;
    XTime t0;
    XTime t1;
    XTime_GetTime(&t0);

    for (unsigned i = 0; i < bnn_data::kImageCount; ++i) {
        std::uint32_t prediction = 0;

        if (!bnn.runImage(bnn_data::kImages[i],
                          bnn_data::kImageBytes,
                          &prediction,
                          kPollTimeout)) {
            xil_printf("Image %u timed out, status=0x%08x\r\n",
                       i,
                       static_cast<unsigned>(bnn.status()));
            return 1;
        }

        const std::uint32_t expected = bnn_data::kExpectedOutputs[i];
        const bool ok = ((prediction & 0xffu) == expected);
        if (ok) {
            ++pass;
        }

        xil_printf("image %u: pred=%u expected=%u %s\r\n",
                   i,
                   static_cast<unsigned>(prediction & 0xffu),
                   static_cast<unsigned>(expected),
                   ok ? "PASS" : "FAIL");
    }

    XTime_GetTime(&t1);
    const std::uint64_t ps_ticks = static_cast<std::uint64_t>(t1 - t0);

    xil_printf("Passed %u/%u images\r\n", pass, bnn_data::kImageCount);
    xil_printf("Accelerator busy cycles: %u\r\n",
               static_cast<unsigned>(bnn.cycleCount()));
    xil_printf("PS timer ticks: 0x%08x%08x\r\n",
               static_cast<unsigned>(ps_ticks >> 32),
               static_cast<unsigned>(ps_ticks));

    return (pass == bnn_data::kImageCount) ? 0 : 1;
}
