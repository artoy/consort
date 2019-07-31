open Ast
open RefinementTypes
open Sexplib.Std
open Std
open SimpleChecker.SideAnalysis
    
module SM = StringMap
module SS = StringSet
module P = Paths

type concr_ap = P.concr_ap

type pred_loc =
  | LCond of int
  | LArg of string * string
  | LReturn of string
  | LOutput of string * string
  | LAlias of int
  | LLet of int
  | LCall of int * string
  | LNull of int
  | LFold of int

let loc_to_string =
  let labeled_expr s i = Printf.sprintf "%s@%d" s i in
  let fn_nm_loc = Printf.sprintf "fn %s %s %s" in
  let fn_loc = Printf.sprintf "fn %s %s" in
  function
  | LCond i -> labeled_expr "if" i
  | LArg (f,a) -> fn_nm_loc f "Arg" a
  | LReturn f -> fn_loc f "Ret"
  | LOutput (f,a) -> fn_nm_loc f "Out" a
  | LAlias i -> labeled_expr "alias" i
  | LLet i -> labeled_expr "let" i
  | LCall (i,a) -> labeled_expr a i
  | LNull i -> labeled_expr "ifnull" i
  | LFold i -> labeled_expr "fold" i

type pred_context = {
  fv: refine_ap list;
  loc: pred_loc;
  target_var: concr_ap
}

type funenv = funtype SM.t
type tenv = typ SM.t

type ownership_type = (unit, float) RefinementTypes._typ
type o_theta = ownership_type RefinementTypes._funtype StringMap.t
type o_solution = ((int,ownership_type StringMap.t) Hashtbl.t * o_theta)
type type_hints = int -> (SimpleTypes.r_typ StringMap.t) option

type oante =
  | ORel of ownership * [ `Eq | `Ge | `Gt ] * float
  | OAny of oante list [@@deriving sexp]

let sexp_of_tenv = SM.sexp_of_t ~v:sexp_of_typ

type tcon = {
  env: (Paths.concr_ap * concr_refinement * nullity) list;
  ante: concr_refinement;
  conseq: concr_refinement;
  owner_ante: oante list;
  nullity: nullity
}[@@deriving sexp]

type ocon =
  (* Constraint ownership variable n to be 1 *)
  | Write of ownership
  (* ownership has to be greater than 0 *)
  | Live of ownership
  (* ((r1, r2),(r1',r2')) is the shuffling of permissions s.t. r1 + r2 = r1' + r2' *)
  | Shuff of (ownership * ownership) * (ownership * ownership)
  | Split of ownership * (ownership * ownership)
  | Eq of ownership * ownership
  (* For well-formedness: if o1 = 0, then o2 = 0 *)
  | Wf of ownership * ownership [@@deriving sexp]


type context = {
  theta: funenv;
  gamma: tenv;
  ownership: ocon list;
  ovars: int list;
  refinements: tcon list;
  pred_arity: (bool * int) StringMap.t;
  v_counter: int;
  pred_detail: (int,pred_context) Hashtbl.t;
  store_env: int -> tenv -> unit;
  o_info: o_solution;
  type_hints: type_hints;
  iso: SimpleChecker.SideAnalysis.results
}

module Result = struct
  type t = {
    theta: funenv;
    ownership: ocon list;
    ovars: int list;
    refinements: tcon list;
    arity: (bool * int) StringMap.t;
    ty_envs: (int,tenv) Hashtbl.t
  }
end

let t_var_counter = ref 0;;

let fresh_tvar () =
  let v = !t_var_counter in
  incr t_var_counter;
  v

let type_mismatch t1 t2 =
  let tag1 = Obj.repr t1 |> Obj.tag in
  let tag2 = Obj.repr t2 |> Obj.tag in
  (assert (tag1 <> tag2); failwith "Mismatched types")

let alloc_ovar ctxt =
  ({ ctxt with v_counter = ctxt.v_counter + 1; ovars = ctxt.v_counter::ctxt.ovars }, OVar ctxt.v_counter)

let (>>) f g = fun st ->
  let (st',v1) = f st in
  let (st'', v2) = g st' in
  (st'',(v1, v2))

let add_owner_con l ctxt = { ctxt with ownership = l @ ctxt.ownership  }


let constrain_well_formed (ctxt,t) =
  let rec wf_loop last_o acc = function
    | TVar _
    | Int _ -> acc
    | Ref (t,o,_) ->
      let c_acc' = Option.fold ~f:(fun acc last ->
          add_owner_con [Wf (last,o)] acc
        ) ~acc last_o in
      wf_loop (Some o) c_acc' t
    | Tuple (_,tl) ->
      List.fold_left (wf_loop last_o) acc tl
    | Mu (_,_,t) -> wf_loop last_o acc t
  in
  (wf_loop None ctxt t, t)


let update_map v t m =
  SM.remove v m
  |> SM.add v t

let update_type v t ctxt =
  { ctxt with gamma = update_map v t ctxt.gamma }

let add_type v t ctxt =
  let te =
    SM.add v t ctxt.gamma
  in
  { ctxt with gamma = te }

let rec denote_type ?(nullity=`NLive) path (bind: (int * Paths.concr_ap) list) acc t =
  match t with
  | Ref (t',_,_) -> denote_type ~nullity:`NUnk (`ADeref path) bind acc t'
  | Int r ->
    let comp_r = compile_refinement path bind r in
    (path,comp_r,nullity)::acc
  | Tuple (b,t) ->
    let (bind' : (int * Paths.concr_ap) list) = (subst_of_binding path b) @ bind in
    List.mapi (fun i te -> (i,te)) t
    |> List.fold_left (fun acc (i,te) ->
        denote_type ~nullity (`AProj (path,i)) bind' acc te
      ) acc
  | TVar _ -> acc
  | Mu (_,_,t) -> denote_type ~nullity path bind acc t

let with_pred_refl root r =
  match root with
  | `ADeref _ -> r
  | _ -> And (r,Relation { rel_op1 = Nu; rel_cond = "="; rel_op2 = RAp root })

let with_refl ap t =
  map_with_bindings (fun ~under_mu root _ r->
    if under_mu then
      r
    else
      with_pred_refl root r
  ) ap ([],[]) t

let denote_gamma gamma =
  SM.fold (fun v t acc ->
    denote_type (`AVar v) [] acc t
  ) gamma []

let rec split_ref_type ctxt (t,o,n) =
  let (ctxt,(o1,o2)) = (alloc_ovar >> alloc_ovar) ctxt in
  let (ctxt',(t1,t2)) = split_type ctxt t in
  let t1' = Ref (t1,o1,n) in
  let t2' = Ref (t2,o2,n) in
  (add_owner_con [Split (o,(o1, o2))] ctxt', (t1', t2'))
and split_type ctxt t =
  match t with
  | Int _ -> (ctxt, (t,t))
  | Ref (t,o,n) ->
    split_ref_type ctxt (t,o,n)
  | Tuple (b,tl) ->
    let (ctxt',tl1,tl2) = List.fold_right (fun t' (ctxt',tl1,tl2) ->
        let (ctxt'',(t'1,t'2)) = split_type ctxt' t' in
        (ctxt'', t'1::tl1,t'2::tl2)
      ) tl (ctxt,[],[])
    in
    (ctxt',(Tuple (b,tl1),Tuple (b,tl2)))
  | TVar id -> ctxt,(TVar id,TVar id)
  | Mu (a,i,t) ->
    let (ctxt',(t1,t2)) = split_type ctxt t in
    ctxt',(Mu (a,i,t1), Mu (a,i,t2))

let rec unsafe_meet tr town =
  match tr,town with
  | Int r,Int _ -> Int r
  | Ref (r1,_,n), Ref (r2,o,_) ->
    Ref (unsafe_meet r1 r2,OConst o,n)
  | Tuple (b,tl1), Tuple (_,tl2) ->
    Tuple (b,List.map2 unsafe_meet tl1 tl2)
  | Mu (a,i,t1), Mu (_,_,t2) ->
    Mu (a,i,unsafe_meet t1 t2)
  | TVar t,TVar _ -> TVar t
  | _ -> type_mismatch tr town

let meet_arg i c_name ctxt in_t =
  let (_,o_th) = ctxt.o_info in
  if not @@ SM.mem c_name o_th then
    in_t
  else
    let { arg_types; _ } = SM.find c_name o_th in
    let o_in = List.nth arg_types i in
    unsafe_meet in_t o_in

let split_arg ctxt t1 t2 =
  let rec loop ctxt arg_t form_t =
    match arg_t,form_t with
    | Int r,Int _ -> (ctxt,(Int r,Int r))
    | Ref (r1,OConst o,n), Ref (r2,OConst o_const,_) ->
      let (ctxt,(t1,t2)) = loop ctxt r1 r2 in
      let rem = o -. o_const in
      (ctxt,(Ref (t1,OConst rem,n), Ref (t2,OConst o_const,n)))
    | Ref (r1,o,n), Ref (r2,_,_) ->
      let (ctxt',(o1,o2)) = (alloc_ovar >> alloc_ovar) ctxt in
      let (ctxt'',(rn',rn'')) = loop { ctxt' with ownership = Split (o,(o1,o2))::ctxt'.ownership } r1 r2 in
      (ctxt'',(Ref (rn',o1,n), Ref (rn'',o2,n)))
    | Mu (a,i,t1), Mu (_,_,t2) ->
      let (ctxt',(t1',t2')) = loop ctxt t1 t2 in
      (ctxt', (Mu (a,i,t1'), Mu (a,i,t2')))
    | TVar v,TVar _ ->
      (ctxt,(TVar v, TVar v))
    | Tuple (b,tl1), Tuple (_,tl2) ->
      let (ctxt',tl_split) =
        List.combine tl1 tl2
        |> map_with_accum ctxt (fun ctxt (a_t,f_t) ->
            loop ctxt a_t f_t
          )
      in
      let (tl_s1,tl_s2) = List.split tl_split in
      ctxt',(Tuple (b,tl_s1), Tuple (b,tl_s2))
    | _ -> type_mismatch arg_t form_t
  in
  let (ctxt',(t1'rem,t1'form)) = loop ctxt t1 t2 in
  let (ctxt'',_) = constrain_well_formed (ctxt',t1'rem) in
  let (ctxt''',_) = constrain_well_formed (ctxt'',t1'form) in
  ctxt''',t1'rem,t1'form

let add_constraint gamma ctxt ?(o=[]) ante conseq nullity =
  { ctxt with
    refinements = {
      env = gamma;
      ante;
      conseq;
      owner_ante = o;
      nullity
    }::ctxt.refinements
  }

let constrain_owner t1 t2 =
  let rec loop t1 t2 ctxt =
    match t1,t2 with
    | Ref (r1,o1,_),Ref (r2,o2,_) ->
      add_owner_con [Eq (o1,o2)] ctxt
      |> loop r1 r2
    | Int _,Int _ -> ctxt
    | Tuple (_,tl1), Tuple (_,tl2) ->
      List.fold_left2 (fun c te1 te2 ->
          loop te1 te2 c
        ) ctxt tl1 tl2
    | TVar _,TVar _ -> ctxt
    | Mu (_,_,t1'), Mu (_,_,t2') -> loop t1' t2' ctxt
    | _ -> type_mismatch t1 t2
  in
  loop t1 t2

let add_type_implication gamma t1_ t2_ ctxt_ =
  let rec impl_loop ~nullity ctxt t1 t2 =
    match t1,t2 with
    | Int r1, Int r2 -> add_constraint gamma ctxt r1 r2 nullity
    | Ref (t1',_,_), Ref (t2',_,_) -> impl_loop ~nullity:`NUnk ctxt t1' t2'
    | Tuple (_,tl1), Tuple (_,tl2) ->
      List.fold_left2 (impl_loop ~nullity) ctxt tl1 tl2
    | TVar _,TVar _ -> ctxt
    | Mu (_,_,t1'), Mu (_,_,t2') -> impl_loop ~nullity ctxt t1' t2'
    | t1,t2 -> type_mismatch t1 t2
  in
  impl_loop ~nullity:`NLive ctxt_ t1_ t2_

let add_folded_var_implication dg var t1 t2 ctxt =
  let type_compile t : (concr_refinement,ownership) _typ = compile_type t var in
  let v_t =
    type_compile t1
    |> with_refl (`AVar var)
  in
  let to_t = type_compile t2 in
  add_type_implication dg v_t to_t ctxt

let add_var_implication dg gamma var t ctxt =
  add_type_implication dg (compile_type (SM.find var gamma) var |> with_refl (`AVar var)) (compile_type t var) ctxt
  
let ap_is_target target sym_vals ap =
  match ap with
  | #Paths.concr_ap as cr_ap -> cr_ap = target
  | `Sym i -> (List.assoc i sym_vals) = target

let filter_fv path sym_vals fv =
  List.filter (fun free_var -> not @@ ap_is_target path sym_vals free_var) fv

let ext_names = true

let mk_pred_name n target_var loc =
  let c = 
    match loc with
    | LCond i -> Printf.sprintf "join-%d" i
    | LArg (f_name,a_name) -> Printf.sprintf "%s-%s-in" f_name a_name
    | LReturn f_name -> Printf.sprintf "%s-ret" f_name
    | LOutput (f_name, a_name) -> Printf.sprintf "%s-%s-out" f_name a_name
    | LAlias i -> Printf.sprintf "shuf-%d" i
    | LLet i -> Printf.sprintf "scope-%d" i
    | LCall (i,a) -> Printf.sprintf "call-%d-%s-out" i a
    | LNull i -> Printf.sprintf "ifnull-%d" i
    | LFold i -> Printf.sprintf "fold-%d" i
  in
  if ext_names then
    c ^ "-" ^ (Paths.to_z3_ident target_var)
  else
    c ^ "-" ^ (string_of_int n)

let alloc_pred ~ground ~loc ?(add_post_var=false) fv target_var ctxt =
  let n = ctxt.v_counter in
  let arity = (List.length fv) +
      1 + !KCFA.cfa + (* 1 for nu and k for context *)
      (if add_post_var then 1 else 0) (* add an extra variable for post *)
  in
  let p_name = mk_pred_name n target_var loc in
  ({ ctxt with
     v_counter = n + 1;
     pred_arity = StringMap.add p_name (ground,arity) ctxt.pred_arity
   }, p_name)

let make_fresh_pred ~ground ~pred_vars:(fv,target,s_val) ~loc ctxt =
  let fv' = filter_fv target s_val fv in
  let (ctxt',p) = alloc_pred ~ground ~loc fv' target ctxt in
  (ctxt',Pred (p,fv'))

let rec free_vars_contains (r: concr_refinement) v_set =
  let root_pred ap = Paths.has_root_p (fun root -> SS.mem root v_set) ap in
  let imm_is_var ri = match ri with RConst _ -> false | RAp ap -> root_pred ap in
  match r with
  | Pred (_,(pv,_))
  | NamedPred (_,(pv,_))
  | CtxtPred (_,_,(pv,_)) -> List.exists root_pred pv
  | Relation { rel_op1 = op1; rel_op2 = op2; _ } ->
    imm_is_var op2 || (match op1 with
      RImm v -> imm_is_var v | Nu -> false)
  | And (r1, r2) -> free_vars_contains r1 v_set || free_vars_contains r2 v_set
  | _ -> false

let predicate_vars kv =
  List.fold_left (fun acc (k, t) ->
      match t with
      | Int _ -> (`AVar k)::acc
      | _ -> acc
  ) [] kv |> List.rev

let gamma_predicate_vars gamma =
  SM.bindings gamma |> predicate_vars

let with_type t ctxt = (ctxt,t)

let to_tuple b (ctxt,tl) = ctxt, Tuple (b,tl)

let walk_tuple (b: ty_binding) f path fv tl ctxt =
  List.mapi (fun i t -> (i,t)) tl
  |> map_with_accum ctxt (fun ctxt' (i,t) ->
      let fv' =
        List.filter (fun (_,k) ->
          match k with
          | SProj i' when i' = i -> false
          | _ -> true
        ) b
        |> List.map (fun (v,_) -> `Sym v)
        |> (@) fv
      in
      f (`AProj (path,i)) fv' t ctxt'
    )
  |> to_tuple b

let walk_ref f path fv t o n ctxt =
  let (ctxt',t') = f (`ADeref path) fv t ctxt in
  ctxt',Ref (t',o,n)

let map_tuple f b tl =
  Tuple (b,List.map f tl)

let map_ref f t o n =
  Ref (f t, o,n)

let lift_to_refinement ~pred path fv t ctxt = 
  let rec lift_loop ?(under_mu=false) ~pred path fv t ctxt =
    match t with
    | `Int ->
      let (ctxt',r) = pred ~under_mu fv path ctxt in
      (ctxt',Int r)
    | `Ref t' ->
      let (ctxt',ov) = alloc_ovar ctxt in
      walk_ref (lift_loop ~under_mu ~pred) path fv t' ov `NUnk ctxt'
    | `Tuple stl ->
      let i_stl = List.mapi (fun i st -> (i,st)) stl in
      let b = List.filter (fun (_,t) -> t = `Int) i_stl
        |> List.map (fun (i,_) -> (fresh_tvar (),SProj i))
      in
      walk_tuple b (lift_loop ~under_mu ~pred) path fv stl ctxt
    | `Mu (id,t) ->
      let (ctxt',t') = lift_loop ~under_mu ~pred path fv t ctxt in
      let rec gen_sub acc t = match t with
        | TVar _
        | Int _ -> acc
        | Mu (_,_,r)
        | Ref (r,_,_) -> gen_sub acc r
        | Tuple (b,tl) ->
          List.fold_left gen_sub (
              List.fold_left (fun acc' (b,_) ->
                (b,fresh_tvar ())::acc'
              ) acc b) tl 
      in
      let sub = gen_sub [] t' in
      let rec sub_loop path fv t ctxt =
        match t with
        | TVar id' when id' = id ->
          let rec do_sub inner_path inner_fv orig_t ctxt =
            match orig_t with
            | TVar _ -> ctxt,orig_t
            | Int _ ->
              let (ctxt',p) = pred ~under_mu:true inner_fv inner_path ctxt in
              (ctxt',Int p)
            | Ref (r,_,n) ->
              let (ctxt',o') = alloc_ovar ctxt in
              walk_ref do_sub inner_path inner_fv r o' n ctxt'
            | Mu _ -> failwith "pass"
            | Tuple (b,tl) ->
              let b' = List.map (fun (old_sym,p) ->
                  (List.assoc old_sym sub, p)
                ) b in
              walk_tuple b' do_sub inner_path fv tl ctxt
          in
          let (ctxt'',t_subbed) = do_sub path fv t' ctxt' in
          ctxt'',Mu (sub,id,t_subbed)
        | TVar _
        | Mu _ -> failwith "PASS"
        | Int _ -> ctxt,t
        | Ref (r,o,n) ->
          walk_ref sub_loop path fv r o n ctxt
        | Tuple (b,tl) ->
          walk_tuple b sub_loop path fv tl ctxt
      in
      sub_loop path fv t' ctxt'
    | `TVar id -> ctxt,TVar id
  in
  lift_loop ~under_mu:false ~pred path fv t ctxt
  |> constrain_well_formed

let lift_src_ap = function
  | AVar v -> `AVar v
  | ADeref v -> `ADeref (`AVar v)
  | AProj (v,i) -> `AProj (`AVar v,i)
  | APtrProj (v,i) -> `AProj (`ADeref (`AVar v), i)

let remove_var_from_pred ~loc ~curr_te ~oracle ~under_mu:ground path (sym_vars,sym_val) r context =
  let curr_comp = compile_refinement path sym_val r in
  if oracle curr_comp path then
    let (ctxt',new_pred) = make_fresh_pred ~ground ~loc ~pred_vars:(sym_vars,path,sym_val) context in
    let new_comp = compile_refinement path sym_val new_pred in
    let ctxt'' = add_constraint curr_te ctxt' (curr_comp |> with_pred_refl path) new_comp `NUnk in
    (ctxt'',new_pred)
  else
    (context,r)

let remove_var_from_type ~loc ~curr_te ~oracle root_var in_scope t context =
  let staged = remove_var_from_pred ~loc ~curr_te ~oracle in
  walk_with_bindings staged root_var (in_scope,[]) t context

let rec get_ref_aps = function
  | And (r1,r2) -> get_ref_aps r1 @ get_ref_aps r2
  | NamedPred (_,(fv,_))
  | Pred (_,(fv,_))
  | CtxtPred (_,_,(fv,_)) -> fv
  | ConstEq _
  | Top -> []
  | Relation { rel_op1; rel_op2; _ } ->
    let get_imm = function
      | RAp r -> [r]
      | RConst _ -> []
    in
    (get_imm rel_op2) @ (match rel_op1 with
    | Nu -> []
    | RImm i -> get_imm i)

let remove_var ~loc to_remove ctxt =
  let curr_te = denote_gamma ctxt.gamma in
  let in_scope = SM.bindings ctxt.gamma |> List.filter (fun (k,_) -> not (SS.mem k to_remove)) |> predicate_vars in
  let ref_vars = SS.fold (fun var acc ->
      walk_with_bindings (fun ~under_mu:_ root (_,sym_vals) r a ->
        let a' =
          compile_refinement root sym_vals r
          |> get_ref_aps
          |> List.filter (fun p -> not (Paths.has_root var p))
          |> List.map Paths.to_z3_ident
          |> List.fold_left (fun acc nm -> SS.add nm acc) a
        in
        (a',r)
      ) (`AVar var) ([],[]) (SM.find var ctxt.gamma) acc |> fst) to_remove SS.empty
  in
  let removal_oracle = (fun r path ->
    (SS.mem (Paths.to_z3_ident path) ref_vars) || (free_vars_contains r to_remove)
  ) in
  let remove_fn = remove_var_from_type ~loc ~curr_te ~oracle:removal_oracle in
  let updated =
    SM.fold (fun v_name t c ->
      if SS.mem v_name to_remove then
        c
      else
        let (c',t') = remove_fn (`AVar v_name) in_scope t c in
        { c' with gamma = SM.add v_name t' c'.gamma }
    ) ctxt.gamma { ctxt with gamma = SM.empty }
  in
  updated

let lift_imm_op_to_rel = function
  | IVar v -> RAp ((`AVar v) :> concr_ap)
  | IInt n -> RConst n

let lift_relation { rop1; cond; rop2 } =
  Relation { rel_op1 = RImm (lift_imm_op_to_rel rop1); rel_cond = cond; rel_op2 = lift_imm_op_to_rel rop2 }

let dump_env ?(msg) tev =
  (match msg with
  | Some m -> print_endline m;
  | None -> ());
  sexp_of_tenv tev |> Sexplib.Sexp.to_string_hum |> print_endline;
  flush stdout
[@@ocaml.warning "-32"] 

let rec strengthen_eq ~strengthen_type ~target =
  match strengthen_type with
  | Int r ->
    let r' = And (r,Relation {
          rel_op1 = Nu; rel_cond = "="; rel_op2 = RAp (target :> refine_ap)
        })
    in
    Int r'
  | Ref _ -> strengthen_type
  | Tuple (b,tl) ->
    let tl' = List.mapi (fun i t ->
        strengthen_eq ~strengthen_type:t ~target:(Paths.t_ind target i)
      ) tl in
    Tuple (b,tl')
  | Mu _ -> strengthen_type
  | TVar _ -> failwith "Top level unfolded type!!!"

type walk_ctxt = {
  o_stack: ownership list;
  binding: (int * concr_ap) list;
  path: concr_ap;
}

let step_tup wc b i t =
  ({ wc with
    path = `AProj (wc.path,i);
    binding = (subst_of_binding wc.path b) @ wc.binding;
  },t)

let step_ref wc o t =
  ({
    wc with
    path = `ADeref wc.path;
    o_stack = o::wc.o_stack
  },t)

let ctxt_compile_ref wc =
  compile_refinement wc.path wc.binding

let fold_left3i f a l1 l2 l3 =
  let rec inner_loop i acc l1 l2 l3 =
    match l1,l2,l3 with
    | h1::t1,h2::t2,h3::t3 ->
      inner_loop (i+1) (f acc i h1 h2 h3) t1 t2 t3
    | [],[],[] -> acc
    | _ -> raise @@ Invalid_argument "differing lengths"
  in
  inner_loop 0 a l1 l2 l3

let constrain_heap_path (cmp: [< `Ge | `Gt | `Eq]) =
  List.map (fun o -> ORel (o,cmp,0.0))

let ctxt_gt wc = constrain_heap_path `Gt wc.o_stack
let ctxt_any_eq wc =
  match wc.o_stack with
  (* just false *)
  | [] -> [ORel (OConst 1.0,`Eq,0.0)]
  | l -> [OAny (constrain_heap_path `Eq l)]

let all_const_o ctxt =
  List.for_all (function
  | OConst _ -> true
  | _ -> false) ctxt.o_stack

let all_live_o ctxt =
  List.for_all (function
  | OConst o -> o > 0.0
  | _ -> failwith "Called with symbolic ownership path") ctxt.o_stack

let unsafe_extract_pred = function
  | Pred (i,(fv,_)) -> (i,fv)
  | _ -> failwith "You broke an invariant somewhere I guess :("

let unsafe_split_ref = function
  | Ref (r,o,n) -> r,o,n
  | _ -> failwith "You were supposed to give me a ref :("

let combine_concr_preds (c1,ct1) (c2,ct2) c_out =
  let out_live = all_live_o c_out in
  let t1_live = all_live_o c1 in
  let t2_live = all_live_o c2 in
  if (not out_live) || ((not t1_live) && (not t2_live)) then
    Top
  else if t1_live && t2_live then
    And (ct1,ct2)
  else if t1_live then
    ct1
  else
    (assert t2_live; ct2)

let generalize_pred root out_type combined_pred =
  let rec gen_ap_loop ap ~exc ~k =
    if ap = root then
      k (root :> refine_ap) out_type
    else
      match ap with
      | `APre v -> exc ~pre:true (`APre v)
      | `AVar v -> exc ~pre:false (`AVar v)
      | `ADeref ap' ->
        gen_ap_loop ap'
          ~exc:(fun ~pre _ ->
            if pre then
              exc ~pre (ap :> refine_ap)
            else
              failwith @@ "Free deref rooted outside target " ^ (string_of_type out_type) ^ " " ^ P.to_z3_ident root
          )
          ~k:(fun _ t ->
            match t with
            | Ref (t',_,_) -> k (ap :> refine_ap) t'
            | _ -> assert false)
      | `AProj (ap',i) -> 
        gen_ap_loop ap'
          ~exc:(fun ~pre _ -> exc ~pre (ap :> refine_ap))
          ~k:(fun _ t ->
            match t with
            | Tuple (b,tl) ->
              let (s,_) = List.find (fun (_,sym_ap) ->
                  match sym_ap with
                  | SProj i' when i' = i -> true
                  | _ -> false) b in
              k (`Sym s) (List.nth tl i)
            | _ -> assert false
          )
  in
  let gen_ap ap = gen_ap_loop ap ~exc:(fun ~pre:_ t -> t) ~k:(fun ap _ -> ap) in
  let rec gen_loop = function
    | Top -> Top
    | ConstEq n -> ConstEq n
    | And (r1,r2) -> And (gen_loop r1,gen_loop r2)
    | Relation r -> Relation (RefinementTypes.map_relation gen_ap r)
    | Pred (i,(fv,_)) -> Pred (i,List.map gen_ap fv)
    | CtxtPred (i1,i2,(fv,_)) -> CtxtPred (i1,i2,List.map gen_ap fv)
    | NamedPred (nm,(fv,_)) -> NamedPred (nm,List.map gen_ap fv)
  in
  gen_loop combined_pred

(* apply_matrix walks t1, t2 and out_type in parallel. At each leaf
   node, it generates a constrain on out_type's refinements based
   on the ownerships along the paths from the roots of t1 and t2 to the leaf.
*)
let apply_matrix ?pp_constr ~t1 ?(t2_bind=[]) ~t2 ?(force_cons=true) ~out_root ?(out_bind=[]) ~out_type ctxt =
  let g = denote_gamma ctxt.gamma in
  let pp = match pp_constr with
    | None -> (fun ~under_mu:_ _ p -> p)
    | Some f -> f in
  let rec inner_loop ~under_mu (c1,t1) (c2,t2) (c_out,out_t) ctxt =
    match t1,t2,out_t with
    | Tuple (b1,tl1), Tuple (b2,tl2), Tuple (b_out,tl_out) ->
      let st1 = step_tup c1 b1 in
      let st2 = step_tup c2 b2 in
      let st3 = step_tup c_out b_out in
      fold_left3i (fun c ind t1' t2' t_out' ->
        inner_loop ~under_mu
          (st1 ind t1')
          (st2 ind t2')
          (st3 ind t_out')
          c
      ) ctxt tl1 tl2 tl_out
    | Ref (t1',o1,_), Ref (t2',o2,_), Ref (t_out',o_out,_) ->
      inner_loop ~under_mu
        (step_ref c1 o1 t1')
        (step_ref c2 o2 t2')
        (step_ref c_out o_out t_out')
        ctxt
    | TVar _,TVar _,TVar _ ->
      ctxt
    | Mu (_,_,t1'), Mu (_,_,t2'), Mu (_,_,out_t') ->
      inner_loop ~under_mu:true (c1,t1') (c2,t2') (c_out,out_t') ctxt
    | Int r1,Int r2,Int out_r ->
      let gen_constraint =
        (force_cons) ||
        (not @@ List.for_all all_const_o [c1; c2; c_out])
      in
      let c_out_r = ctxt_compile_ref c_out out_r in
      let c_r1 = ctxt_compile_ref c1 r1 in
      let c_r2 = ctxt_compile_ref c2 r2 in
      if gen_constraint then
        let mk_constraint oante ante =
          pp ~under_mu c1.path @@ {
            env = g;
            ante = ante;
            conseq = c_out_r;
            owner_ante = (ctxt_gt c_out) @ oante;
            nullity = `NUnk
          }
        in
        let cons = [
          mk_constraint ((ctxt_gt c1) @ (ctxt_gt c2)) @@ And (c_r1,c_r2);
          mk_constraint ((ctxt_any_eq c1) @ (ctxt_gt c2)) @@ c_r2;
          mk_constraint ((ctxt_gt c1) @ (ctxt_any_eq c2)) @@ c_r1;
          pp ~under_mu c1.path @@ {
            env = g;
            ante = Top;
            conseq = c_out_r;
            owner_ante = ctxt_any_eq c_out;
            nullity = `NUnk
          }
        ] in
        let (ctxt',d_list) = ctxt in
        ({ ctxt' with refinements =
             cons @ ctxt'.refinements },d_list)
      else
        let (i,_) = unsafe_extract_pred c_out_r in
        let comb_pred = combine_concr_preds (c1,c_r1) (c2,c_r2) c_out in
        let gen_pred = generalize_pred out_root out_type comb_pred in
        let (ctxt',d_list) = ctxt in
        (ctxt',(i,gen_pred)::d_list)
    | _ -> failwith @@ Printf.sprintf "Mismatched types %s + %s = %s"
          (string_of_type t1)
          (string_of_type t2)
          (string_of_type out_t)
  in
  let mk_ctxt b t =
    ({
      path = out_root;
      binding = b;
      o_stack = []
    },t)
  in
  inner_loop ~under_mu:false
    (mk_ctxt [] t1)
    (mk_ctxt t2_bind t2)
    (mk_ctxt out_bind out_type)
    (ctxt,[])

let rec push_subst bind = function
  | Int r ->
    let sigma = List.map (fun (i,v) -> (i,`AVar v)) bind in
    Int (partial_subst sigma r)
  | Ref (t,o,n) -> map_ref (push_subst bind) t o n
  | Tuple (b,tl) ->
    let b_ext = List.map (fun (i,v) -> (i,SVar v)) bind in
    Tuple (b_ext @ b, tl)
  | TVar id -> TVar id
  | Mu (i,a,t) -> Mu (i,a,push_subst bind t)

let sub_pdef : (string * (refine_ap list, refine_ap) refinement) list -> (typ -> typ) =
  function
  | [] -> (fun t -> t)
  | sub_assoc ->
    map_refinement (function
      | (Pred (i,_) as r) -> List.assoc_opt i sub_assoc |> Option.value ~default:r
      | r -> r)

let rec assign_patt ~let_id ?(count=0) ctxt p t =
  match p,t with
  | PNone, _ -> (count,ctxt,p)
  | p,Mu (a,i,t') ->
    assign_patt ~let_id ~count ctxt p @@ unfold ~gen:fresh_tvar a i t'
  | PVar v,_ -> (count,add_type v t ctxt,p)
  | PTuple t_patt,Tuple (b,tl) ->
    let (count',closed_patt) = List.fold_right2 (fun p t (c_acc,p_acc) ->
        match p,t with
        | PNone, Int _ ->
          let t_name = Printf.sprintf "__t_%d_%d" let_id c_acc in
          (succ c_acc,(PVar t_name)::p_acc)
        | _ -> (c_acc,p::p_acc)
      ) t_patt tl (count,[]) in
    let var_subst = List.map (fun (sym_var,b) ->
        match b with
        | SVar v -> (sym_var,v)
        | SProj i ->
          let bound_var =
            match List.nth closed_patt i with
            | PVar v -> v
            | _ -> assert false
          in
          (sym_var,bound_var)
      ) b in
    let (count',ctxt',t_patt') = List.fold_left2 (fun (count_acc,ctxt_acc,patt_acc) sub_p sub_t ->
        let (id,ctxt,p) = assign_patt ~let_id ~count:count_acc ctxt_acc sub_p @@ push_subst var_subst sub_t in
        (id,ctxt,p::patt_acc)
      ) (count',ctxt,[]) closed_patt tl in
    (count',ctxt',PTuple (List.rev t_patt'))
  | _,TVar _ -> failwith "Attempt to assign raw tvar to variable"
  | PTuple _,_ -> failwith @@ "Attempt to deconstruct value of non-tuple type: " ^ (string_of_type t)

let rec collect_bound_vars acc patt =
  match patt with
  | PVar v -> SS.add v acc
  | PTuple pl -> List.fold_left collect_bound_vars acc pl
  | PNone -> acc

(* t is the type of the location on the RHS that is being bound (and destructed
   by assignment to patt *)
let rec strengthen_type ?root t patt ctxt =
  let maybe_strengthen_patt v ctxt' =
    match root with
    | None -> ctxt
    | Some p ->
      let t' = SM.find v ctxt'.gamma in
      ctxt'
      |> update_type v @@ strengthen_eq ~strengthen_type:t' ~target:p
  in
  match t,patt with
  | Int _,PVar v ->
    maybe_strengthen_patt v ctxt
    |> with_type @@ strengthen_eq ~strengthen_type:t ~target:(`AVar v)
  | Ref _,_ ->
    (ctxt,t)
  | Tuple (b,tl),PVar v ->
    let tl' = List.mapi (fun i t ->
        strengthen_eq ~strengthen_type:t ~target:(`AProj ((`AVar v),i))
      ) tl in
    maybe_strengthen_patt v ctxt
    |> with_type @@ Tuple (b,tl')
  | Tuple (b,tl),PTuple pl ->
    let ind_tl = List.mapi (fun i t -> (i,t)) tl in
    let (ctxt',tl') = List.fold_right2 (fun (i,t) p (ctxt_acc,tl_acc) ->
        let sub_root = Option.map (fun r -> Paths.t_ind r i) root in
        let (c_acc',t') = strengthen_type ?root:sub_root t p ctxt_acc in
        (c_acc', t'::tl_acc)
      ) ind_tl pl (ctxt,[]) in
    (ctxt', Tuple (b,tl'))
  | (TVar _ | Mu _),_ -> (ctxt,t)
  | _ -> assert false

let rec strengthen_let patt rhs ctxt =
  let lkp_ref v = match SM.find v ctxt.gamma with
    | Ref (r,o,n) -> (r,o,n)
    | _ -> failwith "not a ref"
  in
  match patt,rhs with
  | PNone,_ -> ctxt
  | _,Const _
  | _,Mkref RNone
  | _,Mkref (RInt _)
  | _,Nondet
  | _,Null
  | _,Call _ -> ctxt
  | _,Var v ->
    let t = SM.find v ctxt.gamma in
    let (ctxt',t') = strengthen_type ~root:(`AVar v) t patt ctxt in
    update_type v t' ctxt'
  | _,Deref v ->
    let (t,o,n) = lkp_ref v in
    let (ctxt',t') = strengthen_type t patt ctxt in
    update_type v (Ref (t',o,n)) ctxt'
  | (PVar v),Mkref (RVar v') ->
    let (t,o,n) = lkp_ref v in
    let t' = strengthen_eq ~strengthen_type:t ~target:(`AVar v') in
    update_type v (Ref (t',o,n)) ctxt
  | (PTuple pl),Tuple vl ->
    (* .... why would you do this? *)
    List.fold_left2 (fun acc p_sub i_lit ->
        match i_lit with
        | RInt _ | RNone -> acc
        | RVar v -> strengthen_let p_sub (Var v) acc
      ) ctxt pl vl
  | (PVar v),Tuple vl ->
    let pt = SM.find v ctxt.gamma in
    let rec collect ind c tl vl =
      match tl,vl with
      | [],[] -> ([],c)
      | (e_t::ttl,RNone::tvl) | (e_t::ttl,RInt _::tvl) ->
        let (tl',c') = collect (ind + 1) c ttl tvl in
        (e_t::tl',c')
      | (e_t::ttl,(RVar v')::tvl) ->
        let (tl',c') = collect (ind + 1) c ttl tvl in
        let v_type = SM.find v' ctxt.gamma in
        let vt' = strengthen_eq ~strengthen_type:v_type ~target:(`AProj ((`AVar v),ind)) in
        let e_t' = strengthen_eq ~strengthen_type:e_t ~target:(`AVar v') in
        (e_t'::tl', update_type v' vt' c')
      | _ -> failwith "type and value lengths don't match"
    in
    begin
      match pt with
      | Tuple (b,tl) ->
        let (tl',c') = collect 0 ctxt tl vl in
        update_type v (Tuple (b,tl')) c'
      | _ -> failwith "not a tuple type?"
    end
  | _ -> failwith "Ill-typed pattern (simple checker broken?)"


let shuffle_owners t1 t2 t1' t2' =
  let rec loop t1 t2 t1' t2' ctxt =
    match t1,t2,t1',t2' with
    | Int _,Int _,Int _,Int _ -> ctxt
    | Ref (r1,o1,_),Ref (r2,o2,_), Ref (r1',o1',_), Ref(r2',o2',_) ->
      loop r1 r2 r1' r2' @@
        { ctxt with
          ownership = Shuff ((o1,o2),(o1',o2')) :: ctxt.ownership }
    | Tuple (_,tl1), Tuple (_,tl2), Tuple (_,tl1'), Tuple (_,tl2') ->
      let orig_tl = List.combine tl1 tl2 in
      let new_tl = List.combine tl1' tl2' in
      List.fold_left2 (fun ctxt' (te1,te2) (te1',te2') ->
        loop te1 te2 te1' te2' ctxt'
      ) ctxt orig_tl new_tl
    | Mu (_,_,m1), Mu (_,_,m2), Mu (_,_,m1'), Mu (_,_,m2') ->
      loop m1 m2 m1' m2' ctxt
    | TVar _, TVar _, TVar _, TVar _ -> ctxt
    | _ -> failwith "Type mismatch (simple checker broken?)"
  in
  loop t1 t2 t1' t2'
      

let rec post_update_type = function
  | Int _ -> false
  | Tuple (_,tl) -> List.exists post_update_type tl
  | Ref _ -> true
  | TVar _ | Mu _ -> failwith "Bare recursive type"

let sum_ownership t1 t2 out ctxt =
  let rec loop t1 t2 out ctxt =
    match t1,t2,out with
    | Int _, Int _, Int _ -> ctxt
    | Ref (r1,o1,_), Ref (r2,o2,_), Ref (ro,oo,_) ->
      loop r1 r2 ro
        { ctxt with ownership = (Split (oo,(o1,o2)))::ctxt.ownership}
    | Tuple (_,tl1), Tuple (_,tl2), Tuple (_,tl_out) ->
      fold_left3i (fun ctxt _ e1 e2 e_out ->
          loop e1 e2 e_out ctxt) ctxt tl1 tl2 tl_out
    | Mu (_,_,t1'), Mu (_,_,t2'), Mu (_,_,out') ->
      loop t1' t2' out' ctxt
    | TVar _,TVar _, TVar _ -> ctxt
    | _ -> failwith "Mismatched types (simple checker broken?)"
  in
  loop t1 t2 out ctxt

let remove_sub ps ctxt =
  List.fold_left (fun c (i,_) ->
    { c with pred_arity =
        StringMap.remove i c.pred_arity }) ctxt ps

let meet_loop t_ref t_own =
  let rec loop t_ref t_own =
    match t_ref,t_own with
    | Int r,Int () -> Int r
    | Ref (t_ref',_,n),Ref (t_own',o,_) ->
      Ref (loop t_ref' t_own', OConst o,n)
    | Tuple (b,tl_ref), Tuple (_,tl_own) ->
      let tl_ref_cons = List.map2 loop tl_ref tl_own in
      Tuple (b,tl_ref_cons)
    | Mu (i,a,t1), Mu (_,_,t2) ->
      Mu (i,a,loop t1 t2)
    | TVar v,TVar _ -> TVar v
    | _ -> type_mismatch t_ref t_own
  in
  loop t_ref t_own

let meet_ownership st_id (o_envs,_) ap t =
  Hashtbl.find_opt o_envs st_id
  |> Option.map (fun o_env -> 
      map_ap ap (fun o_typ ->
        meet_loop t o_typ) (fun s -> SM.find s o_env)
    )
  |> Option.value ~default:t

let meet_gamma st_id o_info =
  SM.mapi (fun v t ->
    meet_ownership st_id o_info (`AVar v) t)

let meet_out i callee ctxt t =
  let (_,o_th) = ctxt.o_info in
  SM.find_opt callee o_th
  |> Option.map (fun { output_types; _ } ->
      unsafe_meet t @@ List.nth output_types i
    )
  |> Option.value ~default:t

let rec unfold_once = function
  | Int r -> Int r
  | Ref (r, o,n) -> map_ref unfold_once r o n
  | Tuple (b,tl) ->
    map_tuple unfold_once b tl
  | Mu (a,i,t) -> unfold ~gen:fresh_tvar a i t
  | TVar _ -> assert false

let constrain_fold  ~unfolded:(unfolded_t,unfolded_v) ~folded:(folded_t,_) ctxt =
  let folded_unfold = unfold_once folded_t in
  let folded_c = compile_type_path folded_unfold (`AVar unfolded_v) in
  ctxt
  |> add_type_implication (denote_gamma ctxt.gamma) (compile_type unfolded_t unfolded_v) folded_c
  |> constrain_owner unfolded_t folded_unfold

let get_type_scheme ?(is_null=false) ~loc id v ctxt =
  ctxt
  |> 
    lift_to_refinement ~pred:(fun ~under_mu fv p ctxt ->
      let (ctxt',p) = alloc_pred ~ground:(under_mu || is_null) ~loc fv p ctxt in
      (ctxt',Pred (p,fv))
    ) (`AVar v) (gamma_predicate_vars ctxt.gamma) @@
      (ctxt.type_hints id
       |> Option.bind @@ StringMap.find_opt v
       |> Option.unsafe_get ~msg:(Printf.sprintf "Could not infer type of %s" v))

let ground_null (ctxt,t) =
  let rec nullify = function
    | Mu (a,i,t) -> Mu (a,i,nullify t)
    | TVar v -> TVar v
    | Tuple (b,tl) -> map_tuple nullify b tl
    | Ref (t,o,_) -> Ref (nullify t,o,`NNull)
    | Int r -> Int r
  in
  let nulled = nullify t in
  (ctxt,nulled)

let rec to_unk t = match t with
  | Int _
  | TVar _ -> t
  | Tuple (b,tl) ->
    map_tuple to_unk b tl
  | Mu (a,i,t) -> Mu (a,i,to_unk t)
  | Ref (t,o,_) -> map_ref to_unk t o `NUnk

let bind_var v t ctxt =
  { ctxt with gamma = SM.add v t ctxt.gamma }

let rec process_expr ?output_type ?(remove_scope=SS.empty) ctxt (e_id,e) =
  let lkp v = SM.find v ctxt.gamma in
  let lkp_ref v = match lkp v with
    | Ref (r,o,n) -> (r,o,n)
    | _ -> failwith "Not actually a ref"
  in
  let maybe_unfold { iso = { unfold_locs; _ }; _ } t =
    if IntSet.mem e_id unfold_locs then
      unfold_once t
    else
      t
  in
  let ctxt = { ctxt with
    gamma = meet_gamma e_id ctxt.o_info ctxt.gamma;
  } in
  ctxt.store_env e_id @@ ctxt.gamma;
  match e with
  | EVar v ->
    let (ctxt',(t1,t2)) = split_type ctxt @@ lkp v in
    let ctxt'' = update_type v t1 ctxt' in
    begin
      let c_type t = compile_type t "<ret>" in
      match output_type with
      | Some t ->
        let dg = denote_type (`AVar "<ret>") [] (denote_gamma ctxt''.gamma) t2 in
        add_type_implication dg (c_type t2) (c_type t) ctxt''
        |> constrain_owner t2 t
      | None -> ctxt''
    end
    |> remove_var ~loc:(LLet e_id) remove_scope
  | Seq (e1, e2) ->
    let ctxt' = process_expr ctxt e1 in
    process_expr ?output_type ~remove_scope ctxt' e2
      
  | Assign (lhs,IVar rhs,cont) ->
    let (ctxt',(t1,t2)) = split_type ctxt @@ lkp rhs in
    let (orig,o,_)  = lkp_ref lhs in
    let (ctxt'',t2_assign) =
      if IntSet.mem e_id ctxt.iso.fold_locs then
        let ctxt_f,t2_fresh = make_fresh_type ~target_var:(`ADeref (`AVar lhs)) ~fv:(gamma_predicate_vars ctxt.gamma) ~loc:(LFold e_id) orig ctxt' in
        constrain_fold ~folded:(t2_fresh,`ADeref (`AVar lhs)) ~unfolded:(t2,rhs) ctxt_f
        |> with_type t2_fresh
      else
        (ctxt',t2)
    in
    let t2_eq = strengthen_eq ~strengthen_type:t2_assign ~target:(`AVar rhs) in
    let nxt = add_owner_con [Write o] ctxt''
      |> update_type rhs t1
      |> update_type lhs @@ ref_of t2_eq o `NLive
    in
    process_expr ?output_type ~remove_scope nxt cont

  | Assign (lhs,IInt i,cont) ->
    let (_,o,_) = lkp_ref lhs in
    let ctxt' =
      add_owner_con [Write o] ctxt
      |> update_type lhs @@ ref_of (Int (ConstEq i)) o `NLive
    in
    process_expr ?output_type ~remove_scope ctxt' cont

  | Let (PVar v,Mkref (RVar v_ref),((cont_id,_) as exp)) when IntSet.mem e_id ctxt.iso.fold_locs ->
    (* FOLD, EVERYBODY FOLD *)
    let ctxt',fresh_type = get_type_scheme ~loc:(LFold e_id) cont_id v ctxt in
    let (fresh_cont,o,_) = unsafe_split_ref fresh_type in
    let fresh_strengthened = strengthen_eq ~strengthen_type:fresh_cont ~target:(`AVar v_ref) in
    let (ctxt'',(t1,t2)) = split_type ctxt' @@ lkp v_ref in
    let ctxt''' =
      ctxt''
      |> constrain_fold ~folded:(fresh_cont,(`ADeref (`AVar v))) ~unfolded:(t2,v_ref)
      |> update_type v_ref t1
      |> bind_var v @@ ref_of fresh_strengthened o `NLive
      |> add_owner_con [Write o]
    in
    process_expr ?output_type ~remove_scope:(SS.add v remove_scope) ctxt''' exp
  
  | Let (patt,rhs,((cont_id,_) as exp)) ->
    let ctxt,assign_type = begin
      match rhs with
      | Var left_v ->
        let (ctxt',(t1,t2)) = split_type ctxt @@ lkp left_v in
        ctxt'
        |> update_type left_v t1
        |> with_type t2
            
      | Const n -> (ctxt,Int (ConstEq n))
        
      | Nondet -> (ctxt, Int Top)
        
      | Call c -> process_call ~e_id ~cont_id ctxt c
                    
      | Null -> begin
        match patt with
        | PNone -> (ctxt,Int Top (* what *))
        | PTuple _ -> assert false
        | PVar v -> get_type_scheme ~is_null:true ~loc:(LNull e_id) cont_id v ctxt |> ground_null
        end
      | Deref ptr ->
        let (target_type,o,_) = lkp_ref ptr in
        let (ctxt',(t1,t2)) = split_type ctxt target_type in
        let t2_unfold = maybe_unfold ctxt' t2 in
        ctxt'
        |> update_type ptr @@ (ref_of t1 o `NLive)
        |> add_owner_con [Live o]
        |> with_type t2_unfold

      | Ast.Tuple tl ->
        let rec make_tuple c ind i_list =
          match i_list with
          | [] -> (c,[],[])
          | h::t ->
            let (ctxt',ty_rest,b_list) = make_tuple c (ind + 1) t in
            let (ctxt'',ty,flag) = 
            match h with
            | RNone -> (ctxt',Int Top,true)
            | RInt n -> (ctxt',Int (ConstEq n), true)
            | RVar v ->
              let (c_,(t1,t2)) = split_type ctxt' @@ lkp v in
              (update_type v t2 c_,t1, match t1 with Int _ -> true | _ -> false)
            in
            let b_list' = if flag then
                (fresh_tvar (), SProj ind)::b_list
              else b_list
            in
            (ctxt'',ty::ty_rest,b_list')
        in
        let (c',ty_list,t_binding) = make_tuple ctxt 0 tl in
        c',Tuple (t_binding,ty_list)

      | Mkref init' ->
        match init' with
        | RNone -> (ctxt,Ref (Int Top,OConst 1.0,`NLive))
        | RInt n -> (ctxt, Ref (Int (ConstEq n),OConst 1.0,`NLive))
        | RVar r_var ->
          let (ctxt',(t1,t2)) = split_type ctxt @@ lkp r_var in
          update_type r_var t1 ctxt'
          |> with_type @@ Ref (t2,OConst 1.0,`NLive)
                
    end in
    let _,assign_ctxt,close_p = assign_patt ~let_id:e_id ctxt patt assign_type in
    let str_ctxt = strengthen_let close_p rhs assign_ctxt in
    let bound_vars = collect_bound_vars SS.empty close_p in
    process_expr ?output_type ~remove_scope:(SS.union bound_vars remove_scope) str_ctxt exp    
  | Assert (relation,cont) ->
    cont
    |> process_expr ?output_type ~remove_scope @@ add_constraint (denote_gamma ctxt.gamma) ctxt Top (lift_relation relation) `NUnk

  | Alias (v1,src_ap,((next_id,_) as cont)) ->
    let loc = LAlias e_id in
    (* get the variable type *)
    let t1 = lkp v1 |> meet_ownership e_id ctxt.o_info @@ (`AVar v1) in
    (* silly *)
    let ap = lift_src_ap src_ap in
    (* compute the free vars *)
    let free_vars = predicate_vars @@ SM.bindings ctxt.gamma in
    (* Why are we checking unfold_locs here?
       Great question! Short answer: I can't design APIs.
       Long answer: in the simple checker it is much easier to treat
       dereferences in alias expressions as a read, which then gets
       flagged as an unfold (instead of a write, which is an fold). So we allow
       this strangeness until I inevitably mix this up *)
    let is_fold = IntSet.mem e_id ctxt.iso.unfold_locs in
    (* now make a fresh type for the location referred to by ap *)
    (* return back the context, substitution, free vars, old type (o met), and new type (o met) *)
    let (ctxt',subst,ap_fv,t2_sub,t2_sub'),t2' = map_ap_with_bindings ap free_vars (fun (fv,subst) t ->
        (* make the fresh type *)
        let (c_fresh,t') = make_fresh_type ~loc ~target_var:ap ~fv ~bind:subst t ctxt in
        (* pre alias ownership *)
        let t2_sub = meet_ownership e_id ctxt.o_info ap t in
        (* post alias ownership *)
        let t2_sub' = meet_ownership next_id ctxt.o_info ap t' in
        (c_fresh,subst,fv,t2_sub,t2_sub'),t2_sub'
      ) lkp
    in
    (* get all free variables referred to in the predicate of t2 that are also
       addressable from t1 (i.e., not memory locations *)
    let ap_fv_const = List.filter (function
      | #Paths.concr_ap as cr -> Paths.is_const_ap cr
      | `Sym i -> List.assoc i subst |> Paths.is_const_ap
      ) ap_fv
    in
    (* If the sets of FV are not equal, then we have to force the
       generation of new predicates for T1 that do not have free
       variables referring to memory locations *)
    let force_v1_cons = List.length ap_fv_const <> List.length ap_fv in
    (* Generate a fresh type for t1 with these free variables *)
    let (ctxt'',t1_sym') = make_fresh_type ~loc ~target_var:(`AVar v1) ~fv:ap_fv_const ~bind:subst t1 ctxt' in
    (* now t1' is a fresh type with the same shape at t1, but with
       fresh predicates potentially referring to (unbound!) to
       symbolic variables bound by t2's dependent type. We now push
       the substitution for t2 into t1'sym (so a tuple var $2 is
       tranformed into foo->1 as appropriate) *)
    let t1' =
      meet_ownership next_id ctxt.o_info (`AVar v1) t1_sym'
      |> map_refinement @@ partial_subst subst
    in
    (* now t1' and t2' refer to the same sets of free variables: any symbolic variables
       appearing in t1' and t2' are bound by tuple types
       
       Finally, we may have to unfold t2' to generate correct constraints
    *)
    let (t2_constr,t2_constr') = if is_fold then (unfold_once t2_sub,unfold_once t2_sub') else (t2_sub,t2_sub') in
    let app_matrix = apply_matrix ~t1 ~t2_bind:subst ~t2:t2_constr in
    let rec up_ap ap t2_base' ctxt = match ap with
      | `APre _ -> assert false
      | `AVar v -> update_type v t2_base' ctxt
      | `ADeref ap
      | `AProj (ap,_) -> up_ap ap t2_base' ctxt
    in
    let (ctxt'app,(psub2,psub1)) =
      ctxt''
      |> (app_matrix ~force_cons:is_fold ~out_root:ap ~out_bind:subst ~out_type:t2_constr'
        >> app_matrix ~force_cons:force_v1_cons ~out_root:(`AVar v1) ~out_type:t1')
    in
    let res = ctxt'app
      |> shuffle_owners t1 t2_constr t1' t2_constr'
      |> up_ap ap @@ sub_pdef psub2 t2'
      |> update_type v1 @@ sub_pdef psub1 t1'
      |> remove_sub psub1
      |> remove_sub psub2
    in
    process_expr ?output_type ~remove_scope res cont

  | Cond(v,e1,e2) ->
    let add_pc_refinement cond ctxt =
      let curr_ref = lkp v in
      let branch_refinement = {
        rel_op1 = Nu;
        rel_cond = cond;
        rel_op2 = RConst 0
      } in
      ctxt |>
      update_type v @@ map_refinement (fun r -> And (r,Relation branch_refinement)) curr_ref
    in
    process_conditional
      ?output_type ~remove_scope
      ~tr_path:(add_pc_refinement "=")
      ~fl_path:(add_pc_refinement "!=")
      e_id e1 e2 ctxt
  | NCond (v,e1,e2) ->
    process_conditional
      ?output_type ~remove_scope
      ~tr_path:(fun ctxt ->
        let (ctxt',t) = make_fresh_type ~ground:true ~target_var:(`AVar v) ~loc:(LNull e_id) ~fv:(gamma_predicate_vars ctxt.gamma) (lkp v) ctxt |> ground_null in
        update_type v t ctxt'
      )
      ~fl_path:(fun ctxt -> ctxt) e_id e1 e2 ctxt
  | EAnnot (ty_env,next) ->
    let env' =
      List.fold_left (fun acc (k,v) ->
        StringMap.add k v acc
      ) StringMap.empty ty_env in
    next
    |> process_expr ?output_type ~remove_scope { ctxt with gamma = env' }

and process_conditional ?output_type ~remove_scope ~tr_path ~fl_path e_id e1 e2 ctxt =
  let ctxt1 = process_expr ?output_type ~remove_scope (tr_path ctxt) e1 in
  let ctxt2 = process_expr ?output_type ~remove_scope (fl_path {
        ctxt with
        refinements = ctxt1.refinements;
        v_counter = ctxt1.v_counter;
        ownership = ctxt1.ownership;
        pred_arity = ctxt1.pred_arity;
        ovars = ctxt1.ovars
      }) e2 in
  let loc = LCond e_id in
  let u_ctxt = { ctxt2 with gamma = SM.empty } in
  let b1 = SM.bindings ctxt1.gamma in
  let b2 = SM.bindings ctxt2.gamma in
  let predicate_vars = predicate_vars @@ b1 in
  let dg1 = denote_gamma ctxt1.gamma in
  let dg2 = denote_gamma ctxt2.gamma in
  let subsume_types ctxt ~target_var t1 t2 =
    let (ctxt',t'fresh) = make_fresh_type ~loc ~target_var:(`AVar target_var) ~fv:predicate_vars t1 ctxt in
    let t' = to_unk t'fresh in
    let c_up =
      add_folded_var_implication dg1 target_var t1 t' ctxt'
      |> add_folded_var_implication dg2 target_var t2 t'
      |> constrain_owner t1 t'
      |> constrain_owner t2 t'
    in
    (c_up,t')
  in
  List.fold_left2 (fun ctxt (k1,t1) (k2,t2) ->
    assert (k1 = k2);
    let (ctxt',t) = subsume_types ctxt ~target_var:k1 t1 t2 in
    add_type k1 t ctxt'
  ) u_ctxt b1 b2

and make_fresh_type ?(ground=false) ~target_var ~loc ~fv ?(bind=[]) t ctxt =
  walk_with_bindings ~o_map:(fun c _ ->
    alloc_ovar c
  ) (fun ~under_mu p (sym_vars,sym_vals) _ context ->
    make_fresh_pred ~ground:(under_mu || ground) ~loc ~pred_vars:(sym_vars,p,sym_vals) context
  ) target_var (fv,bind) t ctxt
  |> constrain_well_formed
    
and process_call ~e_id ~cont_id ctxt c =
  let arg_bindings = List.mapi (fun i k ->
      (i,k,SM.find k ctxt.gamma)) c.arg_names
  in
  let p_vars = predicate_vars @@ List.map (fun (_,k,v) -> (k,v)) arg_bindings in
  
  let inst_symb ~add_post ~under_mu path (fv_raw,sym_vals) f_refinement =
    let fv = if add_post && (not under_mu) then (`AVar "!pre")::fv_raw else fv_raw in
     match f_refinement with
     | InfPred p -> 
       CtxtPred (c.label,p,filter_fv path sym_vals fv)
     | True -> Top
     | BuiltInPred f -> NamedPred (f,fv)
  in
  let inst_concr ~add_post ~under_mu target_var (fv,subst) f_refinement =
    let symb_out = inst_symb ~add_post ~under_mu target_var (fv,subst) f_refinement in
    compile_refinement target_var subst symb_out
  in
  let input_env = ctxt.gamma |> denote_gamma in
  let callee_type = SM.find c.callee ctxt.theta in
  let inst_fn_type f = List.map (fun (a,t) ->
      map_with_bindings f (`AVar a) (p_vars,[]) t
    )
  in
  
  let concr_in_t = List.combine c.arg_names callee_type.arg_types
    |> inst_fn_type @@ inst_concr ~add_post:false
    |> List.mapi (fun i t ->
        meet_arg i c.callee ctxt t
      )
  in
  let symb_out_t = List.combine c.arg_names callee_type.output_types
    |> inst_fn_type @@ inst_symb ~add_post:true in
  
  let in_out_types = List.combine concr_in_t symb_out_t in
  (* TODO: consistently use this function *)
  let post_type_vars = gamma_predicate_vars ctxt.gamma in
  let updated_ctxt = List.fold_left2 (fun acc (i,k,arg_t) (in_t,out_t) ->
      let loc = LCall (c.label,k) in
      let concretize_arg_t t = compile_type t k |> with_refl (`AVar k) in
      let constrain_in t ctxt =
        let concr_arg_type = concretize_arg_t t in
        add_type_implication input_env concr_arg_type in_t ctxt
        |> constrain_owner concr_arg_type in_t
      in
      
      if post_update_type arg_t then
        let ap = `AVar k in
        let arg_t_o = meet_ownership e_id acc.o_info ap arg_t in
        let (ctxt',resid,formal) = split_arg acc arg_t_o in_t in
        let out_owner = meet_out i c.callee ctxt' out_t in
        (* the (to be) summed type, shape equiv to resid_eq and out_t_eq *)
        let (ctxt'',fresh_type_) = make_fresh_type ~target_var:ap ~loc ~fv:post_type_vars resid ctxt' in
        let fresh_type_own = meet_ownership cont_id ctxt''.o_info ap fresh_type_ in
        let concr_arg_type = concretize_arg_t arg_t in
        
        let (ctxt''',psub) = apply_matrix
            ~pp_constr:(fun ~under_mu path constr  ->
              if under_mu then
                constr
              else
                let pre_type =
                  match map_ap path (fun t -> t) (fun _ -> concr_arg_type) with
                  | Int r -> with_pred_refl path r
                  | _ -> failwith "I've made a terrible mistake"
                in
                {constr with
                  env = (`AVar "!pre",pre_type,`NUnk)::constr.env }
            )
            ~t1:resid
            ~t2:out_owner
            ~force_cons:true
            ~out_root:ap
            ~out_type:fresh_type_own
            ctxt''
        in
        
        (* now the magic *)
        ctxt'''
        (* constrain the formal half of the arg type *)
        |> constrain_in formal
        |> sum_ownership resid out_owner fresh_type_own
        |> update_type k @@ sub_pdef psub fresh_type_own
        |> remove_sub psub
      else
        constrain_in arg_t acc
    ) ctxt arg_bindings in_out_types
  in
  let result = map_with_bindings (inst_symb ~add_post:false) (`AVar "dummy") (p_vars,[]) callee_type.result_type in
  (updated_ctxt, result)

let process_function_bind ctxt fdef =
  let arg_names = fdef.args in
  let f_typ = SM.find fdef.name ctxt.theta in
  let typ_template = List.combine arg_names f_typ.arg_types in
  let fv = predicate_vars typ_template in
  let inst_symb ~post n t =
    map_with_bindings (fun ~under_mu path (fv,sym_vals) p ->
      let base_fv = filter_fv path sym_vals fv in
      let pred_args = if post && (not under_mu) then
          ((P.pre path) :> refine_ap)::base_fv
        else
          base_fv
      in
      match p with
        | InfPred id -> Pred (id,pred_args)
        | _ -> assert false
    ) (`AVar n) (fv,[]) t
  in
  let init_env = List.fold_left (fun g (n,t) ->
      let inst = inst_symb ~post:false n t in
      let (g',inst') =
        walk_with_path (fun ~under_mu path p g ->
          if under_mu then
            (g,p)
          else
            let pre_var = P.to_z3_ident path in
            (SM.add pre_var (Int Top) g, And (p, Relation { rel_op1 = Nu; rel_cond = "="; rel_op2 = RAp (path :> refine_ap) }))
            
        ) (`APre n) inst g
      in
      SM.add n inst' g'
    ) SM.empty typ_template
  in
  let result_type = inst_symb ~post:false "Ret" f_typ.result_type in
  let ctxt' = process_expr ~output_type:result_type ~remove_scope:SS.empty { ctxt with gamma = init_env } fdef.body in
  let out_typ_template = List.combine arg_names f_typ.output_types in
  let result_denote = ctxt'.gamma |> denote_gamma in
  List.fold_left (fun acc (v,out_ty) ->
    let out_refine_type = inst_symb ~post:true v out_ty in
    add_var_implication result_denote acc.gamma v out_refine_type acc
    |> constrain_owner (SM.find v acc.gamma) out_refine_type
  ) ctxt' out_typ_template

let process_function ctxt fdef =
  let c = process_function_bind ctxt fdef in
  { c with gamma = SM.empty }

let print_pred_details t =
  Hashtbl.iter (fun k { fv; loc; target_var } ->
    Printf.fprintf stderr "%d: >>\n" k;
    Printf.fprintf stderr "  Free vars: [%s]\n" @@ String.concat ", " @@ List.map refine_ap_to_string fv;
    Printf.fprintf stderr "  Target var: %s\n" @@ refine_ap_to_string target_var;
    Printf.fprintf stderr "  At: %s\n<<\n" @@ loc_to_string loc
  ) t

let propagate_grounding refine pred =
  let seed = StringMap.bindings pred |> List.filter (fun (_,(b,_)) -> b) |> List.map fst |> StringSet.of_list in
  let rec get_pred_name = function
    | Pred (nm,_)
    | CtxtPred (_,nm,_) -> StringSet.singleton nm
    | And (r1,r2) -> StringSet.union (get_pred_name r1) (get_pred_name r2)
    | _ -> StringSet.empty
  in
  let rec propagate_loop s =
    let c = StringSet.cardinal s in
    let s' = List.fold_left (fun acc {ante; conseq; nullity; _ } ->
        if nullity = `NLive then
          acc
        else
          let ante_nm = get_pred_name ante in
          if StringSet.is_empty @@ StringSet.inter acc ante_nm then
            acc
          else
            StringSet.union acc @@ get_pred_name conseq
      ) s refine
    in
    if c = (StringSet.cardinal s') then
      s'
    else
      propagate_loop s'
  in
  let to_ground = propagate_loop seed in
  StringMap.mapi (fun k (_,n) ->
    (StringSet.mem k to_ground,n)
  ) pred

let infer ~print_pred ~save_types ?o_solve ~intrinsics (st,type_hints,iso) (fns,main) =
  let init_fun_type ctxt f_def =
    let lift_simple_type ~post ~loc =
      lift_to_refinement ~pred:(fun ~under_mu fv path ctxt ->
        let (ctxt',i) = alloc_pred ~ground:under_mu ~add_post_var:(post && (not under_mu)) ~loc fv path ctxt in
        (ctxt',InfPred i))
    in
    let gen_arg_preds ~post ~loc fv arg_templ ctxt = List.fold_right (fun (k,t) (acc_c,acc_ty) ->
        let fv' = List.filter (function
          | `AVar v when v = k -> false
          | _ -> true) fv in
        let (ctxt',t') = lift_simple_type ~post ~loc:(loc k) (`AVar k) fv' t acc_c in
        (ctxt',t'::acc_ty)
      ) arg_templ (ctxt,[])
    in
    let simple_ftype = SM.find f_def.name st in
    let arg_templ = List.combine f_def.args simple_ftype.SimpleTypes.arg_types in
    let free_vars = List.filter (fun (_,t) -> t = `Int) arg_templ |> List.map (fun (n,_) -> (`AVar n)) in
    let (ctxt',arg_types) = gen_arg_preds ~post:false ~loc:(fun k -> LArg (f_def.name,k)) free_vars arg_templ ctxt in
    let (ctxt'',output_types) = gen_arg_preds ~post:true ~loc:(fun k -> LOutput (f_def.name,k)) free_vars arg_templ ctxt' in
    let (ctxt''', result_type) =
      lift_simple_type ~post:false (`AVar "RET") ~loc:(LReturn f_def.name) free_vars simple_ftype.SimpleTypes.ret_type ctxt''
    in
    { ctxt''' with
      theta = SM.add f_def.name {
          arg_types; output_types; result_type
        } ctxt'''.theta
    }
  in
  let ty_envs = Hashtbl.create 10 in
  let store_env =
    if save_types then
      Hashtbl.add ty_envs
    else
      (fun _ _ -> ())
  in
  let initial_ctxt = {
    theta = intrinsics;
    gamma = SM.empty;
    ownership = [];
    ovars = [];
    refinements = [];
    pred_arity = StringMap.empty;
    v_counter = 0;
    pred_detail = Hashtbl.create 10;
    store_env;
    o_info = (match o_solve with
    | Some e -> e
    | None -> (Hashtbl.create 10,SM.empty));
    type_hints;
    iso
  } in
  let ctxt = List.fold_left init_fun_type initial_ctxt fns in
  let ctxt' = List.fold_left process_function ctxt fns in
  let { pred_detail; refinements; ownership; ovars; pred_arity; theta; _ } = process_expr ctxt' main in
  let pred_arity = propagate_grounding refinements pred_arity in
  if print_pred then print_pred_details pred_detail;
  Result.{
    ownership;
    ovars;
    refinements;
    theta;
    arity = pred_arity;
    ty_envs 
  }
