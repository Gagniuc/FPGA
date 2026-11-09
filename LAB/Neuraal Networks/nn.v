
module nn (
    input  wire clk,
    input  wire sensor,
    output wire ldr_power,
    input  wire S1,
    input  wire S2,
    input  wire KEY3,
    input  wire KEY4,
    output wire led1,
    output wire led2,
    output wire led3,
    output wire buzzer
);
    // LDR: PIN_98 -> LDR -> PIN_103 -> 10k -> GND
    assign ldr_power = 1'b1;

    // Sincronizare si filtrare digitala (5 ms)
    reg [1:0] light_sync = 0;
    reg light = 0;
    reg [17:0] debounce = 0;
    always @(posedge clk) begin
        light_sync <= {light_sync[0], sensor};
        if (light_sync[1] == light)
            debounce <= 0;
        else if (debounce == 18'd249999) begin
            light <= light_sync[1];
            debounce <= 0;
        end
        else
            debounce <= debounce + 1'b1;
    end

    // Butoane active LOW (S3=KEY3, S4=KEY4)
    reg [1:0] b1 = 2'b11, b2 = 2'b11;
    reg [1:0] b3 = 2'b11, b4 = 2'b11;
    reg p1 = 1, p2 = 1, p3 = 1;
    always @(posedge clk) begin
        b1 <= {b1[0], S1};
        b2 <= {b2[0], S2};
        b3 <= {b3[0], KEY3};
        b4 <= {b4[0], KEY4};
        p1 <= b1[1];
        p2 <= b2[1];
        p3 <= b3[1];
    end
    wire reset_nn = !b4[1];
    wire press1 = p1 && !b1[1];
    wire press2 = p2 && !b2[1];
    wire press3 = p3 && !b3[1];

    // Achizitie noua timp de o secunda, pornita la apasare.
    // Duty = numar de esantioane HIGH din 100;
    // edges = numar de tranzitii, saturat la 15.
    reg [18:0] tick10ms = 0;
    reg [6:0] n = 0, bright_sum = 0;
    reg [3:0] edge_sum = 0;
    reg previous_light = 0;
    reg [1:0] capture_label = 0;
    reg [1:0] finished_label = 0;
    reg [6:0] f_bright = 0;
    reg [3:0] f_edges = 0;
    reg window_ready = 0;

    wire [6:0] bright_next = bright_sum + {6'b0, light};
    wire [3:0] edge_next =
        (light != previous_light && edge_sum != 4'd15) ?
            edge_sum + 1'b1 : edge_sum;

    always @(posedge clk) begin
        window_ready <= 1'b0;
        if (reset_nn) begin
            tick10ms <= 0;
            n <= 0;
            bright_sum <= 0;
            edge_sum <= 0;
            previous_light <= light;
            capture_label <= 0;
            finished_label <= 0;
            f_bright <= 0;
            f_edges <= 0;
        end
        else if (capture_label == 0 && (press1 || press2 || press3)) begin
            // Nu folosim fereastra veche: pornim de la zero!
            capture_label <= press1 ? 2'd1 :
                             press2 ? 2'd2 : 2'd3;
            tick10ms <= 0;
            n <= 0;
            bright_sum <= 0;
            edge_sum <= 0;
            previous_light <= light;
        end
        else if (tick10ms == 19'd499999) begin
            tick10ms <= 0;
            previous_light <= light;
            if (n == 7'd99) begin
                n <= 0;
                f_bright <= bright_next;
                f_edges <= edge_next;
                finished_label <= capture_label;
                capture_label <= 0;
                bright_sum <= 0;
                edge_sum <= 0;
                window_ready <= 1'b1;
            end
            else begin
                n <= n + 1'b1;
                bright_sum <= bright_next;
                edge_sum <= edge_next;
            end
        end
        else
            tick10ms <= tick10ms + 1'b1;
    end

    // 3 neuroni-prototip cu invatare online.
    reg [6:0] c1_bright = 0, c2_bright = 0, c3_bright = 0;
    reg [3:0] c1_edges = 0, c2_edges = 0, c3_edges = 0;
    reg [2:0] trained = 0;
    wire trained_all = &trained;

    function [6:0] learn_bright;
        input [6:0] old_v, new_v;
        reg [9:0] z;
        begin
            z = (3 * {3'b0,old_v}) + {3'b0,new_v} + 10'd2;
            learn_bright = z >> 2;
        end
    endfunction
    function [3:0] learn_edges;
        input [3:0] old_v, new_v;
        reg [6:0] z;
        begin
            z = (3 * {3'b0,old_v}) + {3'b0,new_v} + 7'd2;
            learn_edges = z >> 2;
        end
    endfunction

    // Exemplul trebuie sa fie corespunzator clasei etichetate.
    wire pulsed = (f_edges >= 4'd3 &&
                   f_bright >= 7'd10 && f_bright <= 7'd90);
    wire steady = (f_edges <= 4'd1 && f_bright >= 7'd90);
    wire dark   = (f_edges <= 4'd1 && f_bright <= 7'd10);
    wire valid_training =
        (finished_label == 2'd1 && pulsed) ||
        (finished_label == 2'd2 && steady) ||
        (finished_label == 2'd3 && dark);

    reg [21:0] beep_timer = 0;
    reg [23:0] flash_timer = 0;
    reg [1:0] flash_class = 0;
    always @(posedge clk) begin
        if (reset_nn) begin
            trained <= 0;
            c1_bright <= 0; c1_edges <= 0;
            c2_bright <= 0; c2_edges <= 0;
            c3_bright <= 0; c3_edges <= 0;
            beep_timer <= 0;
            flash_timer <= 0;
            flash_class <= 0;
        end
        else begin
            if (beep_timer != 0)
                beep_timer <= beep_timer - 1'b1;
            if (flash_timer != 0)
                flash_timer <= flash_timer - 1'b1;

            if (window_ready && finished_label != 0 && valid_training) begin
                case (finished_label)
                    2'd1: begin
                        c1_bright <= trained[0] ?
                            learn_bright(c1_bright,f_bright) : f_bright;
                        c1_edges <= trained[0] ?
                            learn_edges(c1_edges,f_edges) : f_edges;
                        trained[0] <= 1'b1;
                    end
                    2'd2: begin
                        c2_bright <= trained[1] ?
                            learn_bright(c2_bright,f_bright) : f_bright;
                        c2_edges <= trained[1] ?
                            learn_edges(c2_edges,f_edges) : f_edges;
                        trained[1] <= 1'b1;
                    end
                    2'd3: begin
                        c3_bright <= trained[2] ?
                            learn_bright(c3_bright,f_bright) : f_bright;
                        c3_edges <= trained[2] ?
                            learn_edges(c3_edges,f_edges) : f_edges;
                        trained[2] <= 1'b1;
                    end
                endcase
                // Confirmare DOAR dupa un exemplu valid de o secunda.
                beep_timer <= 22'd3000000;
                flash_timer <= 24'd10000000;
                flash_class <= finished_label;
            end
        end
    end

    function [6:0] abs_bright;
        input [6:0] a, b;
        begin
            abs_bright = (a >= b) ? a-b : b-a;
        end
    endfunction
    function [3:0] abs_edges;
        input [3:0] a, b;
        begin
            abs_edges = (a >= b) ? a-b : b-a;
        end
    endfunction

    // Distanta ponderata: duty + 16 * numar_tranzitii.
    wire [10:0] d1 = {4'b0,abs_bright(f_bright,c1_bright)} +
                      ({7'b0,abs_edges(f_edges,c1_edges)} << 4);
    wire [10:0] d2 = {4'b0,abs_bright(f_bright,c2_bright)} +
                      ({7'b0,abs_edges(f_edges,c2_edges)} << 4);
    wire [10:0] d3 = {4'b0,abs_bright(f_bright,c3_bright)} +
                      ({7'b0,abs_edges(f_edges,c3_edges)} << 4);

    // Egalitatile nu favorizeaza automat LED4.
    wire [1:0] nn_prediction =
        (d1 < d2 && d1 < d3) ? 2'd1 :
        (d2 < d1 && d2 < d3) ? 2'd2 :
        (d3 < d1 && d3 < d2) ? 2'd3 : 2'd0;

    // Validare fizica pentru a evita interpretari absurde.
    wire [1:0] recognition =
        !trained_all ? 2'd0 :
        (nn_prediction == 2'd1 && pulsed) ? 2'd1 :
        (nn_prediction == 2'd2 && steady) ? 2'd2 :
        (nn_prediction == 2'd3 && dark)   ? 2'd3 : 2'd0;

    reg [1:0] shown = 0;
    always @(posedge clk) begin
        if (reset_nn)
            shown <= 0;
        else if (window_ready)
            shown <= (finished_label == 0) ? recognition : 2'd0;
    end

    // led1 = LED4 fizic; led2 = LED3 fizic; led3 = LED2 fizic.
    wire [1:0] displayed = (flash_timer != 0) ? flash_class : shown;
    assign led1 = ~(displayed == 2'd1);
    assign led2 = ~(displayed == 2'd2);
    assign led3 = ~(displayed == 2'd3);
    assign buzzer = (beep_timer == 0) ? 1'b1 : 1'b0;
endmodule
