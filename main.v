`define SRAM_ADDRESS_SIZE 17
`define SRAM_ADDRESS_IGNORED_BITS 7
`define MEMORY_WORD_SIZE 16

module memory_controller (
  input  wire                              ena,
  input  wire                              clk,
  input  wire                              rst_n,
  input  wire [`SRAM_ADDRESS_SIZE - 1 : 0] mem_address,
  input  wire [`MEMORY_WORD_SIZE - 1 : 0]  mem_write_value,
  input  wire                              mem_write_enable,
  output reg  [`MEMORY_WORD_SIZE - 1 : 0]  mem_read_value,
  input  wire                              mem_request,
  output reg                               mem_request_complete,
  output reg                               sram_cs_n,
  output reg                               sram_si,
  input  wire                              sram_so
);
  reg [11:0] counter;

  always @(posedge clk) begin
    if (ena) begin
      if (!rst_n) begin
        counter <= 0;
        sram_cs_n <= 1;
      end else begin
        if (mem_request) begin
          sram_cs_n <= 0;
          // The first seven bits are always 0, 0, 0, 0, 0, 0, 1
          if (counter < 6) begin
            sram_si <= 0;
          end else if (counter == 6) begin
            sram_si <= 1;
          end else if (counter == 7) begin
            // Then the eighth bit is 0 if we're writing, 1 if we're reading.
            sram_si <= !mem_write_enable;
          end else if (counter < 8 + `SRAM_ADDRESS_IGNORED_BITS) begin
            sram_si <= 0;
            // sram_si <= 1;
          end else if (counter < 32) begin
            // Then the next 17 bits are the address.
            //sram_si <= mem_address[`SRAM_ADDRESS_SIZE - (counter - 8 - `SRAM_ADDRESS_IGNORED_BITS) - 1];
            sram_si <= mem_address[counter - 8 - `SRAM_ADDRESS_IGNORED_BITS];
          end else if (counter < 32 + `MEMORY_WORD_SIZE) begin
            if (mem_write_enable) begin
              // Finally we send the bits to write, if relevant.
              sram_si <= mem_write_value[counter - 32];
            end else begin
              // Otherwise we read the bits.
              // $display("Reading bit %d = %d", counter - 32, sram_so);
              mem_read_value[counter - 32] <= sram_so;
            end
          end

          if (counter < 32 + `MEMORY_WORD_SIZE) begin
            counter <= counter + 1;
          end else begin
            counter <= 32 + `MEMORY_WORD_SIZE;
            mem_request_complete <= 1;
            sram_cs_n <= 1;
          end
        end else begin
          counter <= 0;
          mem_request_complete <= 0;
        end
      end
    end else begin
      sram_cs_n <= 1;
    end
  end
endmodule

// PMOD0 is the output for the VGA.
// PMOD1 is the input/output for the SRAM.
//   PMOD1[0]: ~CS
//   PMOD1[1]: SO
//   PMOD1[2]: SIO2
//   PMOD1[3]: SI
//   PMOD1[4]: SCK
//   PMOD1[5]: ~HOLD/SIO3

module micro1 (
  input  wire [7:0] ui_in,      // dedicated inputs
  output wire [7:0] uo_out,     // dedicated outputs
  input  wire [7:0] uio_in,     // bidirectional input path
  output wire [7:0] uio_out,    // bidirectional output path
  output wire [7:0] uio_oe,     // bidir output enable (high=out)
  input  wire       ena,        // high when enabled
  input  wire       clk_100mhz, // clock
  input  wire       rst_n       // reset negated (low to reset)
);
  wire vga_r = uo_out[0];
  wire vga_g = uo_out[1];
  wire vga_b = uo_out[2];
  wire vga_hs = uo_out[3];
  wire vga_vs = uo_out[4];

  reg [`SRAM_ADDRESS_SIZE - 1 : 0] mem_address;
  reg [`MEMORY_WORD_SIZE - 1 : 0]  mem_write_value;
  reg                              mem_write_enable;
  reg [`MEMORY_WORD_SIZE - 1 : 0]  mem_read_value;
  reg                              mem_request;
  reg                              mem_request_complete;

  // Set output directions.
  assign uio_oe[0] = 1;
  assign uio_oe[1] = 0;
  assign uio_oe[2] = 1; // We're pulling up, so output.
  assign uio_oe[3] = 1;
  assign uio_oe[4] = 1;
  assign uio_oe[5] = 1; // We're pulling up, so output.
  // Assign pull-up values.
  assign uio_out[2] = 1;
  assign uio_out[5] = 1;

  reg [3:0] mem_controller_clock_divider = 0;
  always @(posedge clk_100mhz) begin
    mem_controller_clock_divider <= mem_controller_clock_divider + 1;
  end

  // Assign the serial clock.
  assign uio_out[4] = !(mem_controller_clock_divider[3] ^ mem_controller_clock_divider[2]);

  memory_controller memory_controller_inst(
    .ena(ena),
    .clk(mem_controller_clock_divider[3]),
    .rst_n(rst_n),
    .mem_address(mem_address),
    .mem_write_value(mem_write_value),
    .mem_write_enable(mem_write_enable),
    .mem_read_value(mem_read_value),
    .mem_request(mem_request),
    .mem_request_complete(mem_request_complete),
    .sram_cs_n(uio_out[0]),
    .sram_si(uio_out[3]),
    .sram_so(uio_in[1])
  );

  reg [23:0] ctr = 0;
  reg [15:0] scanline = 0;
  reg [31:0] lfsr = 1;

  reg [15:0] line_buffer1 [0:19];
  reg [15:0] line_buffer2 [0:19];
  reg line_flip = 0;
  reg [5:0] line_ctr = 0;
  reg [4:0] line_ptr = 0;

  reg mem_fill = 0;

  wire video_en = (scanline >= 35) && (scanline < 515) && (ctr < 2700);

  // We now figure out which character we're at.
  wire [9:0] offset_scanline = scanline - 35;
  wire [4:0] current_row = offset_scanline[8:4];
  wire [3:0] pixel_y = offset_scanline[3:0];
  // Each pixel is 4 cycles long.
  wire [6:0] current_col = ctr[12:6];
  wire [3:0] pixel_x = ctr[5:2];

  wire [15:0] current_char_pair = current_col >= 40 ? 0 : (line_flip ? line_buffer2[current_col >> 1] : line_buffer1[current_col >> 1]);
  wire [7:0] current_char = current_col[0] ? current_char_pair[7:0] : current_char_pair[15:8];

  // We now interpret the character as a little 2x4 grid.
  wire color = current_char[{pixel_y[3], pixel_y[2], pixel_x[3]}];
  //wire color = (current_col >= 39) | (current_row >= 29);

  // assign vga_r = (lfsr[0] ^ lfsr[7]) & video_en;
  assign vga_r = color & video_en;
  // assign vga_g = (lfsr[1] ^ lfsr[12]) & video_en;
  // assign vga_b = (lfsr[2] ^ lfsr[5]) & video_en;
  assign vga_g = mem_request & video_en;
  // assign vga_g = 0 & video_en;
  //assign vga_b = (mem_request_complete | (pixel_x == 0) | (pixel_y == 0)) & video_en;
  assign vga_b = ((pixel_x == 0) | (pixel_y == 0) & (current_col < 40)) & video_en;

  assign vga_vs = scanline >= 2;
  assign vga_hs = (ctr < 2700) || (ctr > 3000);

  always @(posedge clk_100mhz) begin
    if (ena) begin
      if (!rst_n) begin
        ctr <= 0;
        scanline <= 0;
        line_flip <= 0;
        line_ctr <= 0;
        line_ptr <= 0;
        lfsr <= 1;
        mem_fill <= 1;
        mem_address <= 0;
      end else begin
        lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
        ctr <= ctr + 1;

        if (ctr >= 3200) begin
          ctr <= 0;
          scanline <= scanline < 524 ? scanline + 1 : 0;
          if (offset_scanline[3:0] == 4'b1111) begin
            line_flip <= !line_flip;
            line_ctr <= current_row;
            line_ptr <= 0;
          end
        end

        if (mem_fill) begin
          // Begin filling memory with characters.
          if (!mem_request) begin
            mem_address <= mem_address + 1;
            mem_write_value <= lfsr[15:0];
            mem_write_enable <= 1;
            mem_request <= 1;
          end
          if (mem_request_complete) begin
            mem_request <= 0;
            if (mem_address >= 1200) begin
              mem_fill <= 0;
            end
          end
        end else begin
          // Otherwise, fetch the next line of characters.
          if ((line_ptr < 20) && (!mem_request) && (!mem_request_complete)) begin
            mem_address <= 40 * line_ctr + 2 * line_ptr;
            mem_write_enable <= lfsr[0] & lfsr[1] & lfsr[2] & lfsr[3] & lfsr[4]; // FIXME: Do a random mixture of reads and writes.
            mem_write_value <= lfsr[15:0];
            //mem_write_value <= mem_address;
            // mem_write_value <= 8'hc5;
            // mem_write_enable <= 0;
            mem_request <= 1;
            line_ptr <= line_ptr + 1;
          end
          if (mem_request_complete) begin
            mem_request <= 0;
            if (line_flip) begin
              line_buffer1[line_ptr - 1] <= mem_read_value;
            end else begin
              line_buffer2[line_ptr - 1] <= mem_read_value;
            end
          end

        end
      end
    end
  end
endmodule
