import spi_sram
import cocotb, cocotb.clock
from cocotb.triggers import ClockCycles

@cocotb.test()
async def test_main(dut):
    mem = spi_sram.Sim23LC1024()

    cocotb.start_soon(cocotb.clock.Clock(dut.clk, 10).start())
    dut.ena.value = 1

    async def wait_cycle():
        sram_output = mem.clock(cs=dut.uo_out[0], si=dut.uo_out[1])
        print(f"cs: {dut.uo_out[0].value}, si: {dut.uo_out[1].value}, so: {sram_output.value}")
        if sram_output is not None:
            dut.ui_in[0] = sram_output
        await ClockCycles(dut.clk, 1)

    # Assert reset.
    dut.rst_n.value = 0
    await wait_cycle()
    # Begin simulation.
    dut.rst_n.value = 1

    for _ in range(100):
        await wait_cycle()
