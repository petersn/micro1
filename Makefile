
VERILOG_SOURCES += main.v
TOPLEVEL = main  # module name in verilog
MODULE = test    # python test file
include $(shell cocotb-config --makefiles)/Makefile.sim

