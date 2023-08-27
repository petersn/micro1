`define WORD_SIZE 16
`define REGISTER_COUNT 16
`define CACHE_SIZE 8
`define CACHE_LINE_SIZE_BITS 128
`define ADDRESS_LEN 17
`define ADDRESS_IGNORED_BITS 7
// We need CACHE_TAG_LEN = ADDRESS_LEN - log_2(CACHE_LINE_SIZE_BITS)
`define CACHE_TAG_LEN 13

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
  wire sram_cs;
  wire sram_si;
  wire sram_so;
  assign uo_out[0] = sram_cs;
  assign uo_out[1] = sram_si;
  assign sram_so = ui_in[0];

  // CPU state.
  reg error;
  reg [`WORD_SIZE - 1 : 0] register_file[`REGISTER_COUNT];
  reg [`ADDRESS_LEN - 1 : 0] instruction_pointer;
  reg [`WORD_SIZE - 1 : 0] fetched_instruction;
  reg ifetch_required;
  reg read_instruction;

  // Aliases.
  wire [3:0] regA;
  assign regA = fetched_instruction[11:8];
  wire [3:0] regB;
  assign regB = fetched_instruction[15:12];
  wire [3:0] regDest;
  assign regDest = fetched_instruction[7:4];
  wire [3:0] imm4;
  assign imm4 = fetched_instruction[15:12];
  wire [15:0] imm4SignExtended;
  assign imm4SignExtended = {{12{imm4[3]}}, imm4};
  wire [7:0] imm8;
  assign imm8 = fetched_instruction[15:8];
  wire [15:0] imm8SignExtended;
  assign imm12SignExtended = {{8{imm8[7]}}, imm8};
  wire [11:0] imm12;
  assign imm12 = fetched_instruction[15:4];
  wire [15:0] imm12SignExtended;
  assign imm12SignExtended = {{4{imm12[11]}}, imm12};

  // Memory controller.
  reg [`ADDRESS_LEN - 1 : 0] mem_address;
  reg [`WORD_SIZE - 1 : 0] mem_write_value;
  reg mem_write_enable;
  wire [`WORD_SIZE - 1 : 0] mem_read_value;
  reg mem_request;
  wire mem_request_complete;
  memory_controller memory_controller (
    .ena(ena),
    .clk(clk),
    .rst_n(rst_n),
    .mem_address(mem_address),
    .mem_write_value(mem_write_value),
    .mem_write_enable(mem_write_enable),
    .mem_read_value(mem_read_value),
    .mem_request(mem_request),
    .mem_request_complete(mem_request_complete),
    .sram_cs(sram_cs),
    .sram_si(sram_si),
    .sram_so(sram_so)
  );

  //// Cache state machine.
  // reg [`CACHE_LINE_SIZE_BITS - 1 : 0] cache[`CACHE_SIZE];
  // reg [`CACHE_TAG_LEN - 1 : 0] cache_tags[`CACHE_SIZE];

  always @(posedge clk) begin
    if (ena) begin
      if (!rst_n) begin
        error <= 0;
        instruction_pointer <= 16'h100;
        mem_request <= 0;
        ifetch_required <= 1;
        read_instruction <= 0;
      end else if (!error) begin
        // ========== Main logic begins here ==========

        // If we don't have the instruction fetched, then fetch it.
        if (ifetch_required) begin
          mem_address <= instruction_pointer;
          mem_request <= 1;
          mem_write_enable <= 0;
          if (mem_request_complete) begin
            mem_request <= 0;
            $display("Fetched instruction @%h %b", instruction_pointer, mem_read_value);
            fetched_instruction <= mem_read_value;
            ifetch_required <= 0;
            instruction_pointer <= instruction_pointer + 2;
          end
        end else begin
          case (fetched_instruction[3:0])
            4'b0000: begin
              $display("HCF");
              error <= 1;
            end
            4'b0001: begin
              // Perform an unary operation.
              case (regB)
                4'b0000: begin
                  $display("MOV r%d = r%d", regDest, regA);
                  register_file[regDest] <= register_file[regA];
                end
                4'b0001: begin
                  $display("NOT r%d = ~r%d", regDest, regA);
                  register_file[regDest] <= ~register_file[regA];
                end
                4'b0010: begin
                  $display("NEG r%d = -r%d", regDest, regA);
                  register_file[regDest] <= -register_file[regA];
                end
                4'b0011: begin
                  $display("INC r%d = r%d + 1", regDest, regA);
                  register_file[regDest] <= register_file[regA] + 1;
                end
                4'b0100: begin
                  $display("DEC r%d = r%d - 1", regDest, regA);
                  register_file[regDest] <= register_file[regA] - 1;
                end
              endcase
              ifetch_required <= 1;
            end
            4'b0010: begin
              $display("ADD r%d = r%d + r%d", regDest, regA, regB);
              register_file[regDest] <= register_file[regA] + register_file[regB];
              ifetch_required <= 1;
            end
            4'b0011: begin
              $display("LIT8 r%d = %d", regDest, imm8SignExtended);
              register_file[regDest] <= imm8SignExtended;
              ifetch_required <= 1;
            end
            4'b0100: begin
              $display("LIT8H r%d = %d", regDest, imm8SignExtended);
              register_file[regDest][15:8] <= imm8;
              ifetch_required <= 1;
            end
            4'b0101: begin
              $display("JNZ %d, r%d", $signed(imm8SignExtended), regDest);
              if (register_file[regDest] != 0) begin
                instruction_pointer <= instruction_pointer + imm8SignExtended;
              end
              ifetch_required <= 1;
            end
            4'b0110: begin
              $display("JMP %d", $signed(imm12SignExtended));
              instruction_pointer <= instruction_pointer + imm12SignExtended;
              ifetch_required <= 1;
            end
            4'b0111: begin
              $display("LOAD r%d = [r%d + %d]", regDest, regA, $signed(imm4SignExtended));
              mem_address <= register_file[regA] + imm4SignExtended;
              mem_request <= 1;
              mem_write_enable <= 0;
              if (mem_request_complete) begin
                $display("Loaded %d", mem_read_value);
                mem_request <= 0;
                register_file[regDest] <= mem_read_value;
                ifetch_required <= 1;
              end
            end
            4'b1000: begin
              $display("STORE [r%d + %d] = r%d", regA, $signed(imm4SignExtended), regB);
              mem_address <= register_file[regA] + imm4SignExtended;
              mem_write_value <= register_file[regB];
              mem_request <= 1;
              mem_write_enable <= 1;
              if (mem_request_complete) begin
                $display("Stored");
                mem_request <= 0;
                ifetch_required <= 1;
              end
            end
            default: begin
              $display("BADOP");
              error <= 1;
            end
          endcase
        end
      end
    end
  end
endmodule

module memory_controller (
  input  wire                        ena,
  input  wire                        clk,
  input  wire                        rst_n,
  input  wire [`ADDRESS_LEN - 1 : 0] mem_address,
  input  wire [`WORD_SIZE - 1 : 0]   mem_write_value,
  input  wire                        mem_write_enable,
  output reg [`WORD_SIZE - 1 : 0]    mem_read_value,
  input  wire                        mem_request,
  output reg                         mem_request_complete,
  output reg                         sram_cs,
  output reg                         sram_si,
  input  wire                        sram_so
);
  reg [6 : 0] counter;

  always @(posedge clk) begin
    if (ena) begin
      if (!rst_n) begin
        counter <= 0;
        sram_cs <= 1;
      end else begin
        if (mem_request) begin
          sram_cs <= 0;
          // The first seven bits are always 0, 0, 0, 0, 0, 0, 1
          if (counter < 6) begin
            sram_si <= 0;
          end else if (counter == 6) begin
            sram_si <= 1;
          end else if (counter == 7) begin
            // Then the eighth bit is 0 if we're writing, 1 if we're reading.
            sram_si <= !mem_write_enable;
          end else if (counter < 8 + `ADDRESS_IGNORED_BITS) begin
            sram_si <= 0;
          end else if (counter < 32) begin
            // Then the next 17 bits are the address.
            sram_si <= mem_address[`ADDRESS_LEN - (counter - 8 - `ADDRESS_IGNORED_BITS) - 1];
          end else if (counter < 32 + `WORD_SIZE) begin
            if (mem_write_enable) begin
              // Finally we send the bits to write, if relevant.
              sram_si <= mem_write_value[counter - 32];
            end else begin
              // Otherwise we read the bits.
              $display("Reading bit %d = %d", counter - 32, sram_so);
              mem_read_value[counter - 32] <= sram_so;
            end
          end

          if (counter < 32 + `WORD_SIZE) begin
            counter <= counter + 1;
          end else begin
            counter <= 32 + `WORD_SIZE;
            mem_request_complete <= 1;
            sram_cs <= 1;
          end
        end else begin
          counter <= 0;
          mem_request_complete <= 0;
        end
      end
    end else begin
      sram_cs <= 1;
    end
  end
endmodule
