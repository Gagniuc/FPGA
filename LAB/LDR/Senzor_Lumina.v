
module Senzor_Lumina (
    input wire clk,
    input wire sensor,
    output wire ldr_power,
    input wire S1,
    input wire S2,
    input wire KEY3,
    input wire KEY4,
    output wire led1,
    output wire led2,
    output wire led3,
    output wire buzzer
);

    assign ldr_power = 1'b1;

    reg [1:0] light = 0;

    always @(posedge clk)
        light <= {light[0], sensor};

    // LED4 fizic: lumina detectata
    assign led1 = ~light[1];

    // LED3 fizic: stins in acest test
    assign led2 = 1'b1;

    // LED2 fizic: intuneric detectat
    assign led3 = light[1];

    assign buzzer = 1'b1;

endmodule
