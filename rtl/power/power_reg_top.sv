// Copyright 2026 Polytechnic University of Valencia.
// SPDX-License-Identifier: Apache-2.0
//
// Authors:
// - Jose Daniel Boscá Candel <josedaniel@joboscan.es>

`include "common_cells/registers.svh"

module power_reg_top import power_reg_pkg::*; #(
    parameter obi_pkg::obi_cfg_t ObiCfg = obi_pkg::ObiDefaultConfig,
    parameter type obi_req_t = logic,
    parameter type obi_rsp_t = logic
) (
    input  logic clk_i,
    input  logic rst_ni,

    // OBI interface
    input  obi_req_t obi_req_i,
    output obi_rsp_t obi_rsp_o,

    // Register → HW
    output power_reg2hw_t reg2hw
);

  // ------------------------------------------------------------
  // OBI pipeline
  // ------------------------------------------------------------
  logic valid_q;
  logic we_q;
  logic req_q;

  logic [AddressWidth-1:0] addr_q;
  logic [ObiCfg.IdWidth-1:0] id_q;

  logic obi_err;
  logic [ObiCfg.DataWidth-1:0] obi_rdata;

  // always grant
  always_comb begin
    obi_rsp_o         = '0;
    obi_rsp_o.gnt     = 1'b1;
    obi_rsp_o.rvalid  = valid_q;
    obi_rsp_o.r.rid   = id_q;
    obi_rsp_o.r.rdata = obi_rdata;
    obi_rsp_o.r.err   = obi_err;
  end

  `FF(valid_q, obi_req_i.req,            1'b0, clk_i, rst_ni)
  `FF(we_q,    obi_req_i.a.we,           1'b0, clk_i, rst_ni)
  `FF(req_q,   obi_req_i.req,            1'b0, clk_i, rst_ni)
  `FF(addr_q,  obi_req_i.a.addr[AddressWidth-1:2], '0, clk_i, rst_ni)
  `FF(id_q,    obi_req_i.a.aid,           '0, clk_i, rst_ni)

  // ------------------------------------------------------------
  // Register
  // ------------------------------------------------------------
  logic [1:0] pwr_mode_q, pwr_mode_d;

  `FF(pwr_mode_q, pwr_mode_d, 2'b00, clk_i, rst_ni) // default LIGHT_SLEEP

  // ------------------------------------------------------------
  // Combinational
  // ------------------------------------------------------------
  always_comb begin
    pwr_mode_d = pwr_mode_q;

    obi_rdata = 32'h0;
    obi_err   = 1'b0;

    // WRITE
    if (obi_req_i.req && obi_req_i.a.we) begin
      case ({obi_req_i.a.addr[AddressWidth-1:2],2'b00})
        POWER_MODE_OFFSET: pwr_mode_d = obi_req_i.a.wdata[1:0];
        default:           obi_err = 1'b1;
      endcase
    end

    // READ
    if (req_q && !we_q) begin
      case ({addr_q,2'b00})
        POWER_MODE_OFFSET: obi_rdata = {30'b0, pwr_mode_q};
        default: begin
          obi_rdata = 32'hBADCAB1E;
          obi_err   = 1'b1;
        end
      endcase
    end
  end

  // ------------------------------------------------------------
  // Output to HW
  // ------------------------------------------------------------
  assign reg2hw.pwr_mode = pwr_mode_q;

endmodule
