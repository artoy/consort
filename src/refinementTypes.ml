open Sexplib.Std

type pred_loc =
  | LCond of int
  | LArg of string
  | LReturn of string
  | LOutput of string
  | LAlias of int
  | LLet of int
  | LCall of int


type rel_imm =
  | RAp of Paths.const_ap
  | RConst of int [@@deriving sexp]

type rel_op =
    Nu
  | RImm of rel_imm [@@deriving sexp]

type refinement_rel = {
  rel_op1: rel_op;
  rel_cond: string;
  rel_op2: rel_imm;
} [@@deriving sexp]

type refine_ap = [
  Paths.concr_ap
| `Sym of int
] [@@deriving sexp]

(* 
Pred n,l: A predicate symbol with name n over variables l (nu is implicit)
CtxtPred c,n,l: A Preciate symbol with name n over variables l with explicit context c
Top: unconstrained
Const: the constaint constraint
Eq: equality with variable b
*)
type 'c refinement =
  | Pred of int * 'c
  | CtxtPred of int * int * 'c
  | Top
  | ConstEq of int
  | Relation of refinement_rel
  | And of 'c refinement * 'c refinement
  | NamedPred of string * 'c [@@deriving sexp]

type concr_refinement = (Paths.concr_ap list * Paths.concr_ap) refinement [@@deriving sexp]

type ownership =
    OVar of int
  | OConst of float[@@deriving sexp]

type ap_symb =
  | SVar of string
  | SProj of int [@@deriving sexp]

type ty_binding = (int * ap_symb) list [@@deriving sexp]

type 'a _typ =
  | Int of 'a
  | Ref of 'a _typ * ownership
  | Tuple of ty_binding * ('a _typ) list
[@@deriving sexp]

type arg_refinment =
  | InfPred of int
  | BuiltInPred of string
  | True[@@deriving sexp]

type typ = ((refine_ap list) refinement) _typ [@@deriving sexp]
type ftyp = arg_refinment _typ[@@deriving sexp]

type funtype = {
  arg_types: ftyp list;
  output_types: ftyp list;
  result_type: ftyp
}[@@deriving sexp]

let unsafe_get_ownership = function
  | `Ref (_,o) -> o
  | _ -> failwith "This is why its unsafe"

let ref_of t1 o = Ref (t1, o)

let rec map_refinement f =
  function
  | Int r -> Int (f r)
  | Ref (t,o) -> Ref (map_refinement f t,o)
  | Tuple (b,tl) -> Tuple (b,(List.map (map_refinement f) tl))

let rec to_simple_type = function
  | Ref (t,_) -> `Ref (to_simple_type t)
  | Int _ -> `Int
  | Tuple (_,t) -> `Tuple (List.map to_simple_type t)

let to_simple_funenv = StringMap.map (fun { arg_types; result_type; _ } ->
    {
      SimpleTypes.arg_types = List.map to_simple_type arg_types;
      SimpleTypes.ret_type = to_simple_type result_type;
    })

let subst_pv mapping pl =
  let map_ap = function
    | `Sym i -> List.assoc i mapping
    | #Paths.concr_ap as cp -> cp
  in
  List.map map_ap pl

let partial_subst subst_assoc =
  let subst = List.map (function
    | `Sym i when List.mem_assoc i subst_assoc -> (List.assoc i subst_assoc :> refine_ap)
    | r -> r) in
  let rec loop r =
    match r with
    | Pred (i,pv) -> Pred (i,subst pv)
    | CtxtPred (i1,i2,pv) -> CtxtPred (i1,i2, subst pv)
    | Top -> Top
    | Relation rel -> Relation rel
    | ConstEq ce -> ConstEq ce
    | And (p1,p2) -> And (loop p1, loop p2)
    | NamedPred (nm,pv) -> NamedPred (nm, subst pv)
  in
  loop

let compile_refinement target subst_assoc =
  let subst = subst_pv subst_assoc in
  let rec loop r = 
    match r with
    | Pred (i,pv) -> Pred (i,(subst pv,target))
    | CtxtPred (i1,i2,pv) -> CtxtPred (i1,i2,(subst pv,target))
    | Top -> Top
    | Relation rel -> Relation rel
    | ConstEq ce -> ConstEq ce
    | And (p1,p2) -> And (loop p1, loop p2)
    | NamedPred (nm,pv) -> NamedPred (nm,(subst pv,target))
  in loop

let compile_bindings blist root =
  List.map (fun (k,t) ->
    match t with
    | SVar v -> (k,`AVar v)
    | SProj i -> (k,`AProj (root,i))
  ) blist

let compile_type t1 root : (Paths.concr_ap list * Paths.concr_ap) refinement _typ =
  let rec compile_loop t1 root bindings =
    match t1 with
    | Int r -> Int (compile_refinement root bindings r)
    | Ref (t,o) -> Ref (compile_loop t (`ADeref root) bindings,o)
    | Tuple (b,tl) ->
      let bindings' = bindings @ (compile_bindings b root) in
      let tl' = List.mapi (fun i t ->
          compile_loop t (`AProj (root,i)) bindings'
        ) tl in
      Tuple ([],tl')
  in
  compile_loop t1 (`AVar root) []


let subst_of_binding root = List.map (fun (i,p) ->
    match p with
    | SProj ind -> (i,`AProj (root,ind))
    | SVar v -> (i, `AVar v)
  )

let update_binding path tup_b (fv_ap,sym_vals) =
  let added_bindings = List.map (fun (i,_) -> `Sym i) tup_b in
  let b_vals = subst_of_binding path tup_b in
  let fv_ap' = fv_ap @ added_bindings in
  let sym_vals' = sym_vals @ b_vals in
  (fv_ap',sym_vals')

(* curr_te here and in the following is the type environment
   prior to the removal operation *)
let rec walk_with_bindings ?(o_map=(fun c o -> (c,o))) f root bindings t a =
  match t with
  | Int r ->
    let (a',r') = f root bindings r a in
    (a',Int r')
  | Ref (t',o) ->
    let (a',t'') = walk_with_bindings ~o_map f (`ADeref root) bindings t' a in
    let (a'',o') = o_map a' o in
    (a'',Ref (t'',o'))
  | Tuple (b,tl) ->
    let tl_named = List.mapi (fun i t ->
        let nm = Paths.t_ind root i in
        (nm,t)
      ) tl in
    let bindings' = update_binding root b bindings in
    let rec loop a_accum l =
      match l with
      | [] -> (a_accum,[])
      | (nm,t)::tl ->
        let (acc',t') = walk_with_bindings ~o_map f nm bindings' t a_accum in
        let (acc'',tl') = loop acc' tl in
        (acc'',t'::tl')
    in
    let (a',tl') = loop a tl_named in
    (a',Tuple (b,tl'))

let rec update_nth l i v =
  match l with
  | h::t ->
    if i = 0 then
      v::t
    else
      h::(update_nth t (i - 1) v)
  | [] -> raise @@ Invalid_argument "Bad index"

let map_ap_with_bindings ap fvs f gen =
  let rec inner_loop ap' c =
    match ap' with
    | `AVar v -> c (fvs,[]) (gen v)
    | `ADeref ap ->
      inner_loop ap (fun b t' ->
          match t' with
          | Ref (t'',o) ->
            let (a',mapped) = c b t'' in
            (a',Ref (mapped,o))
          | _ -> failwith "Invalid type for AP"
        )
    | `AProj (ap,i) ->
      inner_loop ap (fun b t' ->
          match t' with
          | Tuple (bind,tl) ->
            let t_sub = List.nth tl i in
            let (a',mapped) = c (update_binding ap bind b) t_sub in
            (a',Tuple (bind, update_nth tl i mapped))
          | _ -> failwith "Invalid type for proj AP"
        )
  in
  inner_loop ap f

let refine_ap_to_string = function
  | #Paths.concr_ap as cp -> Paths.to_z3_ident cp
  | `Sym i -> Printf.sprintf "$%d" i


let alpha = "\xCE\xB1"
let nu = "\xCE\xBD"

let pp_owner =
  let open PrettyPrint in
  function
  | OVar o -> ps @@ Printf.sprintf "$o%d" o
  | OConst f -> ps @@ Printf.sprintf "%f" f

let simplify_ref =
  let rec loop ~ex ~k (r: refine_ap list refinement) =
    match r with
    | Relation _
    | CtxtPred _
    | NamedPred _
    | ConstEq _
    | Pred _ -> k r
    | And (r1,r2) ->
      loop
        ~ex:(fun () ->
          loop ~ex ~k r2)
        ~k:(fun r1' ->
          loop
            ~ex:(fun () -> k r1')
            ~k:(fun r2' -> k @@ And (r1',r2'))
            r2)
        r1
    | Top -> ex ()
  in
  loop ~ex:(fun () -> Top) ~k:(fun r' -> r')

let rec pp_ref =
  let open PrettyPrint in
  let pred_name i = Printf.sprintf "P%d" i in
  let pp_alist o = List.map (fun ap -> ps @@ refine_ap_to_string ap) o in
  let print_pred i o ctxt = pb [
      pf "%s(" @@ pred_name i;
      psep_gen (pf ",@ ") @@ [
        ctxt;
        ps nu
      ] @ (pp_alist o);
      pf ")"
    ]
  in
  let pp_rel_imm = function
    | RAp p -> ps @@ refine_ap_to_string (p :> refine_ap)
    | RConst n -> pi n
  in
  let pp_rel_op = function
    | Nu -> ps nu;
    | RImm i -> pp_rel_imm i
  in
  function
  | Pred (i,o) -> print_pred i o @@ ps alpha
  | CtxtPred (c,i,o) -> print_pred i o @@ pi c
  | Top -> ps "T"
  | ConstEq n -> pf "%s = %d" nu n
  | Relation { rel_op1; rel_cond; rel_op2 } ->
    pb [
        pf "%a@ %s@ %a"
          (ul pp_rel_op) rel_op1
          rel_cond
          (ul pp_rel_imm) rel_op2
      ]
  | NamedPred (s,o) ->
    pb [
        pf "%s(" s;
        psep_gen (pf ",@ ") @@ (ps nu)::(pp_alist o);
        ps ")"
      ]
  | And (r1,r2) ->
    pb [
        pp_ref r1;
        pf "@ /\\@ ";
        pp_ref r2
      ]

let rec pp_type : typ -> Format.formatter -> unit =
  let open PrettyPrint in
  let sym_var = pf "$%d" in
  function
  | Tuple (b,tl) ->
    let bound_vars = List.filter (fun (_,p) ->
        match p with
        | SProj _ -> true
        | _ -> false
      ) b |> List.map (fun (i,p) ->
          match p with
          | SProj ind -> (ind,i)
          | _ -> assert false
        ) in
    let pp_tl = List.mapi (fun ind t ->
        let pp_t = pp_type t in
        if List.mem_assoc ind bound_vars then
          let bound_name = sym_var @@ List.assoc ind bound_vars in
          pb [
            bound_name; ps ":"; sbrk;
            pp_t
          ]
        else
          pp_t
      ) tl in
    pb [
      ps "(";
      psep_gen (pf ",@ ") pp_tl;
      ps ")"
    ]
  | Int r -> pb [
                 pf "{\xCE\xBD:int@ |@ ";
                 simplify_ref r |> pp_ref;
                 ps "}"
               ]
  | Ref (t,o) ->
    pb [
        pp_type t;
        pf "@ ref@ ";
        pp_owner o
      ]
