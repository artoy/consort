%{
	open SurfaceAst

	let list_to_seq x rest =
	  let comp = x::rest in
	  let rev = List.rev comp in
	  let accum = List.hd rev in
	  List.fold_left (fun curr next  ->
					   Seq (next, curr)) accum (List.tl rev)

%}
// values
%token UNIT
%token <int> INT
%token <string> ID
// conditionals
%token IF THEN ELSE
// bindings
%token LET IN MKREF EQ
// BIFs
%token ASSERT ALIAS
// Update
%token ASSIGN
// operators
%token STAR
%token <string> OPERATOR
%token DOT
// connectives
%token SEMI COMMA
// structure
%token RPAREN LPAREN LBRACE RBRACE EOF

%token COLON

%token UNDERSCORE

%type <SurfaceAst.op> op
%type <SurfaceAst.op list> arg_list

%start <SurfaceAst.prog> prog

%%

let prog := ~ = fdef* ; ~ = delimited(LBRACE, expr, RBRACE); EOF; <>

let fdef := name = ID ; args = param_list; body = expr; <>

let param_list :=
  | ~ = delimited(LPAREN, separated_nonempty_list(COMMA, ID), RPAREN); <>
  | UNIT; { [] }

let arg_list :=
  | ~ = delimited(LPAREN, separated_nonempty_list(COMMA, op), RPAREN); <>
  | UNIT; { [] }

let expr :=
  | UNIT; { Unit }
  | ~ = delimited(LBRACE, expr, RBRACE); <>
  | LBRACE; e = expr; SEMI; rest = separated_nonempty_list(SEMI, expr); RBRACE; {
		list_to_seq e rest
	  }
  | LET; lbl = expr_label; p = patt; EQ; ~ = lhs; IN; body = expr; <Let>
  | IF; lbl = expr_label; x = cond_expr; THEN; thenc = expr; ELSE; elsec = expr; <Cond>
  | lbl = pre_label; x = ID; ASSIGN; y = lhs; <Assign>
  | call = fn_call; <Call>
  | ALIAS; lbl = expr_label; LPAREN; x = ID; EQ; y = ap; RPAREN; <Alias>
  | ASSERT; lbl = expr_label; LPAREN; op1 = op; cond = rel_op; op2 = op; RPAREN; { Assert (lbl,{ op1; cond; op2 }) }
  | ~ = var_ref; <>
  | ~ = INT; <Int>

let var_ref :=
  | ~ = ID; ~ = expr_label; <Var>

let ap :=
  | ~ = ID; <Ast.AVar>
  | STAR; ~ = ID; <Ast.ADeref>
  | LPAREN; STAR; id = ID; RPAREN; DOT; ind = INT; { Ast.APtrProj(id, ind) }
  | v = ID; DOT; ind = INT; { Ast.AProj (v, ind) }

let patt :=
  | LPAREN; plist = separated_list(COMMA, patt); RPAREN; <Ast.PTuple>
  | UNDERSCORE; { Ast.PNone }
  | ~ = ID; <Ast.PVar>

let op :=
  | ~ = INT; <`OInt>
  | ~ = ID; <`OVar>
  | STAR; ~ = ID; <`ODeref>
  | UNDERSCORE; { `Nondet }

let ref_op :=
  | o = lhs; { (o :> lhs) }

let cond_expr :=
  | ~ = ID; <`Var>
  | b = bin_op; { (b :> [ `BinOp of (op * string * op) | `Var of string]) }

let bin_op :=
  | o1 = op; op_name = operator; o2 = op; <`BinOp>

let operator :=
  | ~ = OPERATOR; <>
  | EQ; { "=" }
  | STAR; { "*" }

let lhs :=
  | b = bin_op; { (b :> lhs) }
  | o = op; { (o :> lhs) }
  | MKREF; ~ = ref_op; <`Mkref>
  | ~ = fn_call; <`Call>
  | LPAREN; l = separated_list(COMMA, lhs); RPAREN; <`Tuple>

let fn_call := ~ = callee; lbl = expr_label; arg_names = arg_list; <>
let callee ==
  | ~ = ID; <>
  | LPAREN; ~ = operator; RPAREN; <>

let rel_op :=
  | ~ = OPERATOR; <>
  | EQ; { "=" }

let expr_label == COLON; ~ = INT; <> | { LabelManager.register () }
let pre_label == ~ = INT; COLON; <> | { LabelManager.register () }
