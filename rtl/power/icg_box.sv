module icg_box (
  input        E,
  input        CLK, 
  input        TE,
  output logic GCLK
);

logic latch_e;  
logic latch_g;
logic latch_q;

assign latch_e = E || TE;
assign latch_g = !CLK;
assign GCLK = latch_q && CLK;

always @ (*)
  if(latch_g)
     latch_q = latch_e;

endmodule