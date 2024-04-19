`default_nettype none

module top (
  inout wire [7:0] pmod0,
  inout wire [7:0] pmod1,
  inout wire [7:0] pmod2,
  output wire [3:0] ledR,
  output wire [3:0] ledG,
  output wire [3:0] ledB,
  input wire clk_100mhz,
);
  wire [7:0] uio_in;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

  reg rst_n = 0;
  reg [30:0] ctr = 0;

  always @(posedge clk_100mhz) begin
    ctr <= ctr + 1;
    if (ctr > 1000000) begin
      rst_n <= 1;
    end
    // rst_n <= (ctr >= 1000000);
  end

  assign ledR[2:0] = 3'b111;
  assign ledG = 4'b1111;
  assign ledB = {3'b111, rst_n};

  genvar i;
  generate
    for (i = 0; i < 8; i = i + 1) begin : loop
      assign pmod1[i] = uio_oe[i] ? uio_out[i] : 1'bz;
    end
  endgenerate
  assign uio_in = pmod1;

  // instantiate the top-level module
  micro1 micro1_inst(
    .ui_in(pmod2),
    .uo_out(pmod0),
    .uio_in(uio_in),
    .uio_out(uio_out),
    .uio_oe(uio_oe),
    .ena(1),
    .clk_100mhz(clk_100mhz),
    .rst_n(rst_n),
    .led(ledR[3])
  );
endmodule
