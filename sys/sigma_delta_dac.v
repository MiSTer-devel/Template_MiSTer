//
// PWM DAC
//
// MSBI is the highest bit number. NOT amount of bits!
//
module sigma_delta_dac #(parameter MSBI=7, parameter INV=1'b1, parameter AMOUNT_OF_STEPS_PER_SAMPLE=24576000/48000)
(
   output reg      DACout, //Average Output feeding analog lowpass
   input  [MSBI:0] DACin,  //DAC input (excess 2**MSBI)
   input           CLK,
   input           RESET
);

reg [MSBI+2:0] DeltaAdder; //Output of Delta Adder
reg [MSBI+2:0] SigmaAdder; //Output of Sigma Adder
reg [MSBI+2:0] SigmaLatch; //Latches output of Sigma Adder
reg [MSBI+2:0] DeltaB;     //B input of Delta Adder

localparam STEP_RATIO = (1 << 20) / AMOUNT_OF_STEPS_PER_SAMPLE;

shortint step = 0;
reg [MSBI+2:0] InterpolatedDeltaB;

always @(*) InterpolatedDeltaB = (DeltaB * STEP_RATIO * step) >>> 20;
always @(*) DeltaB = {SigmaLatch[MSBI+2], SigmaLatch[MSBI+2]} << (MSBI+1);
always @(*) DeltaAdder = DACin + InterpolatedDeltaB;
always @(*) SigmaAdder = DeltaAdder + SigmaLatch;

always @(posedge CLK or posedge RESET) begin
   if(RESET) begin
      SigmaLatch <= 1'b1 << (MSBI+1);
      DACout <= INV;
   end else begin
      step <= step < AMOUNT_OF_STEPS_PER_SAMPLE ? step + 1 : 0;
      SigmaLatch <= SigmaAdder;
      DACout <= SigmaLatch[MSBI+2] ^ INV;
   end
end

endmodule
