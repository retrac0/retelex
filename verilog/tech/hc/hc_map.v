// hc_map.v -- map Yosys internal gates (after abc -g) onto HC SSI cells.
`timescale 1ns/1ps

module \$_NOT_ (A, Y);
  input A; output Y;
  HC04_INV _TECHMAP_REPLACE_ (.A(A), .Y(Y));
endmodule

module \$_AND_ (A, B, Y);
  input A, B; output Y;
  HC08_AND2 _TECHMAP_REPLACE_ (.A(A), .B(B), .Y(Y));
endmodule

module \$_OR_ (A, B, Y);
  input A, B; output Y;
  HC32_OR2 _TECHMAP_REPLACE_ (.A(A), .B(B), .Y(Y));
endmodule

module \$_NAND_ (A, B, Y);
  input A, B; output Y;
  HC00_NAND2 _TECHMAP_REPLACE_ (.A(A), .B(B), .Y(Y));
endmodule

module \$_NOR_ (A, B, Y);
  input A, B; output Y;
  HC02_NOR2 _TECHMAP_REPLACE_ (.A(A), .B(B), .Y(Y));
endmodule

module \$_XOR_ (A, B, Y);
  input A, B; output Y;
  wire t0, t1, na, nb;
  HC04_INV  i0 (.A(A), .Y(na));
  HC04_INV  i1 (.A(B), .Y(nb));
  HC08_AND2 a0 (.A(A), .B(nb), .Y(t0));
  HC08_AND2 a1 (.A(na), .B(B), .Y(t1));
  HC32_OR2  o0 (.A(t0), .B(t1), .Y(Y));
endmodule

module \$_XNOR_ (A, B, Y);
  input A, B; output Y;
  wire t;
  \$_XOR_ x (.A(A), .B(B), .Y(t));
  HC04_INV i (.A(t), .Y(Y));
endmodule

module \$_MUX_ (A, B, S, Y);
  input A, B, S; output Y;
  wire ns, t0, t1;
  HC04_INV  i  (.A(S), .Y(ns));
  HC08_AND2 a0 (.A(A), .B(ns), .Y(t0));
  HC08_AND2 a1 (.A(B), .B(S),  .Y(t1));
  HC32_OR2  o  (.A(t0), .B(t1), .Y(Y));
endmodule
