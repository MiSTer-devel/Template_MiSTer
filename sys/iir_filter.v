
//  3-tap IIR filter for 2 channels. 
//  Copyright (C) 2020 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

//
//  Can be converted to 2-tap (coeff_x2 = 0, coeff_y2 = 0) or 1-tap (coeff_x1,2 = 0, coeff_y1,2 = 0)
//
module IIR_filter
#(
	parameter coeff_x  =  0.00000774701983513660, // Base gain value for X. Float. Range: 0.0 ... 0.999(9)
	parameter coeff_x0 =  3,                      // Gain scale factor for X0. Integer. Range -7 ... +7
	parameter coeff_x1 =  3,                      // Gain scale factor for X1. Integer. Range -7 ... +7
	parameter coeff_x2 =  1,                      // Gain scale factor for X2. Integer. Range -7 ... +7
	parameter coeff_y0 = -2.96438150626551080000, // Coefficient for Y0. Float. Range -3.999(9) ... 3.999(9)
	parameter coeff_y1 =  2.92939452735121100000, // Coefficient for Y1. Float. Range -3.999(9) ... 3.999(9)
	parameter coeff_y2 = -0.96500747158831091000  // Coefficient for Y2. Float. Range -3.999(9) ... 3.999(9)
)
(
	input         clk,
	input         ce,                         // must be double of calculated rate!
	input         sample_ce,                  // desired output sample rate
	input  [15:0] input_l,  input_r,
	output [15:0] output_l, output_r
);

localparam  [39:0] coeff   = coeff_x * 40'h8000000000;
wire signed [59:0] inp_mul = $signed(inp) * $signed(coeff);

wire [39:0] x = inp_mul[59:20];
wire [39:0] y = x + tap0;

wire [39:0] tap0;
iir_filter_tap #(coeff_x0, coeff_y0) iir_tap_0
(
	.clk(clk),
	.ce(ce),
	.ch(ch),
	.x(x),
	.y(y),
	.z(tap1),
	.tap(tap0)
);

wire [39:0] tap1;
iir_filter_tap #(coeff_x1, coeff_y1) iir_tap_1
(
	.clk(clk),
	.ce(ce),
	.ch(ch),
	.x(x),
	.y(y),
	.z(tap2),
	.tap(tap1)
);

wire [39:0] tap2;
iir_filter_tap #(coeff_x2, coeff_y2) iir_tap_2
(
	.clk(clk),
	.ce(ce),
	.ch(ch),
	.x(x),
	.y(y),
	.z(0),
	.tap(tap2)
);

reg        ch = 0;
reg [15:0] out_l, out_r, out_m;
reg [15:0] inp, inp_m;
always @(posedge clk) if (ce) begin
	ch <= ~ch;
	if(ch) begin
		out_m <= y[35:20];
		inp   <= inp_m;
	end
	else begin
		out_l <= out_m;
		out_r <= y[35:20];
		inp   <= input_l;
		inp_m <= input_r;
	end
end

reg [31:0] out;
always @(posedge clk) if (sample_ce) out <= {out_l, out_r};

assign {output_l, output_r} = out;

endmodule

module iir_filter_tap
#(
	parameter coeff_x,
	parameter coeff_y
)
(
	input         clk,
	input         ce,
	input         ch,
	input  [39:0] x,
	input  [39:0] y,
	input  [39:0] z,
	output [39:0] tap
);

localparam  [23:0] coeff = coeff_y * 24'h200000;
wire signed [60:0] y_mul = $signed(y[36:0]) * $signed(coeff);

function [39:0] x_mul;
	input [39:0] x;
begin
	x_mul = 0;
	if(coeff_x[0])  x_mul =  x_mul + {{4{x[39]}}, x[39:4]};
	if(coeff_x[1])  x_mul =  x_mul + {{3{x[39]}}, x[39:3]};
	if(coeff_x[2])  x_mul =  x_mul + {{2{x[39]}}, x[39:2]};
	if(coeff_x[31]) x_mul = ~x_mul; //cheap NEG
end
endfunction

(* ramstyle = "logic" *) reg [39:0] intreg[2];
always @(posedge clk) if(ce) intreg[ch] <= x_mul(x) - y_mul[60:21] + z;

assign tap = intreg[ch];

endmodule

// simplified IIR 1-tap.
module DC_blocker
(
	input         clk,
	input         ce, // 48/96 KHz

	input         sample_rate,
	input  [15:0] din,
	output [15:0] dout
);

wire [39:0] x  = {din[15], din, 23'd0};
wire [39:0] x0 = x - (sample_rate ? {{11{x[39]}}, x[39:11]} : {{10{x[39]}}, x[39:10]});
wire [39:0] y1 = y - (sample_rate ? {{10{y[39]}}, y[39:10]} : {{09{y[39]}}, y[39:09]});
wire [39:0] y0 = x0 - x1 + y1;

reg  [39:0] x1, y;
always @(posedge clk) if(ce) begin
	x1 <= x0;
	y  <= ^y0[39:38] ? {{2{y0[39]}},{38{y0[38]}}} : y0;
end

assign dout = y[38:23];

endmodule
