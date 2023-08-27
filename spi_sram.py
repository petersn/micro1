import cocotb

class Sim23LC1024:
    SIZE = 0x20000

    def __init__(self):
        self.contents = [[0] * 8] * self.SIZE
        self.input_shift_register = []
        self.output_shift_register = []
        self.mode = "instruction"
        self.address = 0

    def clock(self, cs, si):
        if not cs.value.is_resolvable:
            self.mode = "invalid"
            return cocotb.binary.BinaryValue("z")
        if cs.value == 1:
            self.input_shift_register = []
            self.output_shift_register = []
            self.mode = "instruction"
            return cocotb.binary.BinaryValue("z")
        if self.mode == "invalid":
            self.input_shift_register = []
            self.output_shift_register = []
            return cocotb.binary.BinaryValue("z")
        self.input_shift_register.append(si.value)
        if self.mode == "instruction":
            assert len(self.input_shift_register) <= 32
            if len(self.input_shift_register) == 32:
                instruction = self.input_shift_register[:8]
                self.address = sum(
                    2**(23 - i) * bit.value
                    for i, bit in enumerate(self.input_shift_register[8:32])
                )
                # The spec says that the first seven bits of the address are ignored.
                # But for now, I'd like to enforce that those bits are all zero.
                #self.address %= self.SIZE
                if instruction == [0, 0, 0, 0, 0, 0, 1, 1]:
                    print("SRAM: read at address %x" % self.address)
                    self.mode = "read"
                    self.output_shift_register = self.contents[self.address][:]
                elif instruction == [0, 0, 0, 0, 0, 0, 1, 0]:
                    print("SRAM: write at address %x" % self.address)
                    self.mode = "write"
                else:
                    # I don't implement the other six instructions for now.
                    raise ValueError("Unknown instruction: %s" % instruction)
                self.input_shift_register = []
        elif self.mode == "read":
            assert len(self.input_shift_register) <= 8
            if len(self.input_shift_register) == 8:
                self.address = (self.address + 1) % self.SIZE
                self.output_shift_register = self.contents[self.address][:]
                self.input_shift_register = []
        elif self.mode == "write":
            assert len(self.input_shift_register) <= 8
            if len(self.input_shift_register) == 8:
                self.contents[self.address] = self.input_shift_register[:]
                self.address = (self.address + 1) % self.SIZE
                self.input_shift_register = []
        if self.output_shift_register:
            return self.output_shift_register.pop(0)
        else:
            return cocotb.binary.BinaryValue("z")


if __name__ == "__main__":
    mem = Sim23LC1024()
    assert mem.clock(cs=1, si=0) is None
    # Issue write instruction.
    for bit in [0, 0, 0, 0, 0, 0, 1, 0]:
        assert mem.clock(cs=0, si=bit) is None
    # Give the all zero address.
    for bit in [0] * 24:
        assert mem.clock(cs=0, si=bit) is None
    # Write to the first bit.
    for bit in [1, 0, 1, 0, 1, 1, 1, 1]:
        assert mem.clock(cs=0, si=bit) is None
    # Write to the second byte.
    for bit in [0, 0, 1, 1, 0, 0, 1, 1]:
        assert mem.clock(cs=0, si=bit) is None
    # Disable for one cycle, to reset the instruction.
    assert mem.clock(cs=1, si=0) is None
    # Read the second byte.
    for bit in [0, 0, 0, 0, 0, 0, 1, 1]:
        assert mem.clock(cs=0, si=bit) is None
    # Send the first 23 bits of the address in.
    for bit in [0] * 23:
        assert mem.clock(cs=0, si=bit) is None
    # The very last bit starts reading!
    assert mem.clock(cs=0, si=1) == 0
    for should_get in [0, 1, 1, 0, 0, 1, 1]:
        assert mem.clock(cs=0, si=0) == should_get
