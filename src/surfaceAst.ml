module A = Ast

type 'a r_init = 'a

type op = [
  | `OVar of string
  | `OInt of int
  | `ODeref of string
  | `Nondet
(*  | `Field of op * string*)
] 
type call = string * int * (op list)


type lhs = [
  | op
  | `Mkref of lhs r_init
  | `BinOp of op * string * op
  | `Call of call
  | `Tuple of lhs list
]

type relation = {
  op1: op;
  cond: string;
  op2: op
}

type patt = A.patt

type exp =
  | Unit
  | Var of string
  | Int of int
  | Cond of int * [`Var of string | `BinOp of op * string * op] * exp * exp
  | Assign of string * lhs
  (*  | FAssign of string * string * lhs*)
  | Let of int * patt * lhs * exp
  | Alias of int * string * A.ap
  | Assert of relation
  | Call of call
  | Seq of exp * exp

type fn = string * string list * exp
type prog = fn list * exp

module SS = Set.Make(String)
module SM = StringMap

type field_ctxt = SS.t SM.t

let tvar = Printf.sprintf "__t%d"

let alloc_temp count =
  let v = tvar count in
  (count + 1),v

(* let add_fields s ctxt =
 *   let found = SS.fold (fun f stat ->
 *     let new_cont =
 *       match SM.mem f ctxt,stat with
 *       | f,None -> Some f
 *       | f,Some f' when f <> f' -> failwith "Inconsistent fields"
 *       | f,Some f' when f = f' -> stat
 *       | _ -> assert false
 *     in
 *     new_cont
 *     ) s None in
 *   match found with
 *   | None -> failwith "empty record"
 *   | Some true when not (SM.mem (SS.min_elt s) ctxt) ->
 *     failwith "Inconsisent fields"
 *   | Some true ->
 *     let curr_set = ctxt |> SM.find @@ SS.min_elt s in
 *     if SS.equal curr_set s then
 *       ctxt
 *     else
 *       failwith "Inconsistent fields"
 *   | Some false -> SM.add (SS.min_elt s) s ctxt
 * 
 * let rec process_rec kv_list ctxt =
 *   let (ss,ctxt') = List.fold_left (fun (ss,c) (k,v) ->
 *     let ss' = SS.add k ss in
 *     let c' = match v with
 *       | `Record r -> process_rec r c
 *       | _ -> c
 *     in
 *     (ss',c')
 *     ) (SS.empty,ctxt) kv_list in
 *   add_fields ss ctxt'
 * 
 * let rec compute_f e ctxt =
 *   match e with
 *   | Seq(e1,e2)
 *   | Cond (_, _, e1, e2) ->
 *     ctxt
 *     |> compute_f e1
 *     |> compute_f e2
 * 
 *   | Let (_,_,`Mkref (`Record r),e) ->
 *     process_rec r ctxt
 *     |> compute_f e
 *   | Let (_,_,_,e) ->
 *     compute_f e ctxt
 *       
 *   | Alias _
 *   | Assign _
 *   (\*  | FAssign _*\)
 *   | Call _
 *   | Var _
 *   | Int _
 *   | Unit
 *   | Assert _ ->
 *     ctxt *)

let rec simplify_expr ?next count e =
  let get_continuation count = match next with
    | None -> simplify_expr count @@ Int 0
    | Some e' -> simplify_expr count e'
  in
  match e with
  | Unit -> simplify_expr count @@ Int 0
  | Var s -> A.EVar s
  | Int i ->
    bind_in count (`OInt i) (fun _ var -> A.EVar var)
  | Cond (i,`Var v,e1,e2) ->
    A.Cond (i,v,simplify_expr count e1,simplify_expr count e2)
  | Cond (i,(`BinOp _ as b),e1,e2) ->
    bind_in ~ctxt:i count (b :> lhs) (fun c tvar ->
        A.Cond (i,tvar,simplify_expr c e1,simplify_expr c e2)
      )
  | Seq (((Assign _ | Alias _ | Assert _) as ue),e1) ->
    simplify_expr ~next:e1 count ue
  | Seq (e1,e2) ->
    A.Seq (simplify_expr count e1,simplify_expr count e2)
  | Assign (v,l) ->
    lift_to_imm count l (fun c i ->
        A.Assign (v,i,get_continuation c)
      )
  (*    | FAssign (b,f,lhs) ->
        lift_to_imm count lhs (fun c i ->
            A.Assign (b,f,i,get_continuation c)
          )*)
  | Let (i,v,lhs,body) ->
    lift_to_lhs ~ctxt:i count lhs (fun c lhs' ->
        let body' = simplify_expr c body in
        A.Let (i,v,lhs',body')
      )
  | Alias (i,v1,v2) -> 
    A.Alias (i,v1,v2, get_continuation count)
  | Assert { op1; cond; op2 } ->
    lift_to_imm count (op1 :> lhs) (fun c op1' ->
        lift_to_imm c (op2 :> lhs) (fun c' op2' ->
          A.Assert ({ A.rop1 = op1'; A.cond = cond; A.rop2 = op2' }, get_continuation c')
        )
      )
  | Call ((_,i,_) as c) ->
    bind_in ~ctxt:i count (`Call c) (fun _ tvar ->
        A.EVar tvar
      )
and lift_to_lhs ?ctxt count (lhs : lhs) (rest: int -> A.lhs -> A.exp) =
  let k r = rest count r in
  match lhs with
(*  | `Field (b,f_name) ->
    lift_to_var ?ctxt count (b :> lhs) (fun c b_var ->
        rest c @@ A.Field (b_var,f_name)
      )*)
  | `OVar v -> k @@ A.Var v
  | `OInt i -> k @@ A.Const i
  | `ODeref v -> k @@ A.Deref v
  | `Nondet -> k @@ A.Nondet
  | `Call c ->
    lift_to_call count c (fun c' l -> rest c' @@ A.Call l)
  | `BinOp (o1,op_name,o2) ->
    lift_to_var ?ctxt count (o1 :> lhs) (fun c i1 ->
        lift_to_var c (o2 :> lhs) (fun c' i2 ->
          rest c' (A.Call { A.callee = op_name; arg_names = [i1;i2]; label = LabelManager.register ?ctxt () })
        )
      )
  | `Mkref lhs ->
    lift_to_rinit ?ctxt count lhs (fun c' r ->
        rest c' @@ A.Mkref r
      )
  | `Tuple tl -> lift_to_tuple ?ctxt count tl (fun c' tlist ->
                     rest c' @@ A.Tuple tlist
                   )
and lift_to_rinit ?ctxt count (r: lhs) rest =
  let k = rest count in
  match r with
(*  | `Record _ -> bind_in ?ctxt count (`Mkref r) (fun c' var ->
                     rest c' @@ A.RVar var
                   )*)
  | `Nondet -> k A.RNone
  | `OVar v -> k @@ A.RVar v
  | `OInt i -> k @@ A.RInt i
  | #lhs as l ->
    bind_in ?ctxt count l (fun c' var ->
        rest c' @@ A.RVar var
      )
and lift_to_tuple ?ctxt count l rest =
  let rec t_loop c acc kl =
    match kl with
    | [] -> rest c @@ List.rev acc
    | v::l -> lift_to_rinit ?ctxt c v (fun c' lifted ->
                      t_loop c' (lifted::acc) l
                    )
  in
  t_loop count [] l
and lift_to_var ?ctxt c (h: lhs) rest =
  match h with
  | `OVar v -> rest c v
  | _ -> bind_in ?ctxt c h (fun c' tvar ->
             rest c' tvar
           )
and lift_to_imm ?ctxt count (o: lhs) rest =
  match o with
  | `OVar s -> rest count @@ A.IVar s
  | `OInt i -> rest count @@ A.IInt i
  | _ -> bind_in ?ctxt count o (fun c tvar ->
             rest c (A.IVar tvar)
           )
and lift_to_call count (callee,id,args) rest =
  let rec recurse c a k = match a with
    | [] -> k c []
    | h::t -> lift_to_var ~ctxt:id c (h :> lhs) (fun c' var ->
                  recurse c' t (fun c'' l ->
                    k c'' @@ var::l
                  )
                )
  in
  recurse count args (fun c' l ->
    rest c' { A.callee = callee; A.label = id; A.arg_names = l }
  )
and bind_in ?ctxt count lhs k =
  lift_to_lhs ?ctxt count lhs (fun c' lhs' ->
    let (c'',tvar) = alloc_temp c' in
    let to_inst = k c'' tvar in
    A.Let (LabelManager.register ?ctxt (),A.PVar tvar,lhs',to_inst)
  )

let simplify (fns,body) =
  let simpl_fn = List.map (fun (name,args,e) ->
      { A.name = name; A.args = args; A.body = simplify_expr 0 e }
    ) fns in
  let program_body = simplify_expr 0 body in
  (simpl_fn, program_body)
  
