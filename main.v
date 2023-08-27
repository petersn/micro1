
module main (
  input  wire [7:0] ui_in,   // dedicated inputs
  output wire [7:0] uo_out,  // dedicated outputs
  input  wire [7:0] uio_in,  // bidirectional input path
  output wire [7:0] uio_out, // bidirectional output path
  output wire [7:0] uio_oe,  // bidir output enable (high=out)
  input  wire       ena,     // high when enabled
  input  wire       clk,     // clock
  input  wire       rst_n    // reset negated (low to reset)
);
  reg sram_cs;
  reg sram_si;
  wire sram_so;
  assign uo_out[0] = sram_cs;
  assign uo_out[1] = sram_si;
  assign sram_so = ui_in[0];

  // Simple memory controller
  reg [23:0] address;
  always @(posedge clk) begin
    if (ena) begin
      if (!rst_n) begin
        // Reset case
        address <= 0;
      end else begin
        // Do something interesting here?
      end

      sram_cs <= 1;
    end
  end
endmodule
