
module vga_pwm
(
	input         clk,
	input         csync_en,

	input         hsync,
	input         csync,

	input  	  [23:0] din,
	output reg [23:0] dout
);

reg [1:0]  vga_pwm;
always @(posedge clk) begin

	if (csync_en ? ~csync : ~hsync)
		vga_pwm <= vga_pwm + 1'd1; 
	else
		vga_pwm <= 2'd3;
	
	if (vga_pwm < din[17:16] && din[23:18] < 6'b111111)
		dout[23:18] <= din[23:18] + 1'd1;
	else 	
		dout[23:18] <= din[23:18];
		
	if (vga_pwm < din[9:8] && din[15:10] < 6'b111111)
		dout[15:10] <= din[15:10] + 1'd1;
	else 	
		dout[15:10] <= din[15:10];
		
	if (vga_pwm < din[1:0] && din[7:2] < 6'b111111)
		dout[7:2] <= din[7:2] + 1'd1;
	else 	
		dout[7:2] <= din[7:2];

end

endmodule
