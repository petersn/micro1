import spi_sram
import cocotb, cocotb.clock
from cocotb.triggers import ClockCycles

@cocotb.test()
async def test_main(dut):
    mem = spi_sram.Sim23LC1024()
    mem.contents[0x100] = [1, 1, 1, 1, 0, 0, 0, 0]
    mem.contents[0x101] = [1, 1, 1, 1, 0, 0, 0, 0]

    cocotb.start_soon(cocotb.clock.Clock(dut.clk, 10).start())
    dut.ena.value = 1

    async def wait_cycle():
        sram_output = mem.clock(cs=dut.uio_out[4], si=dut.uio_out[5])
        #print(f"cs: {dut.uo_out[0].value}, si: {dut.uo_out[1].value}, so: {sram_output}")
        dut.uio_in[0].value = sram_output
        await ClockCycles(dut.clk, 1, rising=False)

    # Assert reset.
    dut.rst_n.value = 0
    await wait_cycle()
    # Begin simulation.
    dut.rst_n.value = 1

    for _ in range(200):
        await wait_cycle()
