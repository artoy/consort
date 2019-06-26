open Ast
open SimpleTypes

module UnionFind : sig
  type t
  val find: t -> int -> int
  val union: t -> int -> int -> unit
  val mk: (parent:int -> child:int -> unit) -> t
  val new_node: t -> int
end = struct
  type node = {
    id: int;
    mutable parent: node;
    mutable rank: int;
  }
  
  type t = {
    table: (int, node) Hashtbl.t;
    mutable next: int;
    merge_hook : parent:int -> child:int -> unit
  }

  let make_and_add uf =
    let rec node = { id = uf.next; parent = node; rank = 1 } in
    Hashtbl.add uf.table node.id node;
    uf.next <- uf.next + 1;
    node.id

  let mk merge_hook =
    let uf = { table = Hashtbl.create 10; next = 0; merge_hook } in
    (*List.iter (fun r ->
      Some r |> (make_and_add uf) |> ignore
    ) roots;*)
    uf

  let rec compress node =
    if node.parent == node then
      node
    else
      let found = compress node.parent in
      node.parent <- found;
      found

  let find_internal uf id1 =
    let node = Hashtbl.find uf.table id1 in
    (compress node)

  let find uf id1 =
    (find_internal uf id1).id

  let union uf id1 id2 =
    let n1 = find_internal uf id1 in
    let n2 = find_internal uf id2 in
    if n1 == n2 then
      ()
    else begin
      let (new_root,child) = begin
        if n2.rank < n1.rank then
          (n2.parent <- n1; (n1,n2))
        else if n1.rank < n2.rank then
          (n1.parent <- n2; (n2,n1))
        else
          (let (new_root,child) = (n1,n2) in
          child.parent <- new_root;
          new_root.rank <- new_root.rank + 1;
          (new_root,child))
      end in
      uf.merge_hook ~parent:new_root.id ~child:child.id
    end

  let new_node uf = make_and_add uf
end
type 'a c_typ = [
  | `Int
  | `Ref of 'a
  | `Tuple of 'a list
]

type typ = [
  typ c_typ
| `Var of int
]

type c_inst = typ c_typ

type funtyp_v = {
  arg_types_v: int list;
  ret_type_v: int
}

module SM = StringMap
module SS = Set.Make(String)

type funenv = funtyp_v SM.t
type tyenv = typ SM.t
(*
type record_types = {
  rec_of_field: (string,int) Hashtbl.t;
  fields_of_rec: (int,SS.t) Hashtbl.t;
  type_of_field: (string,int) Hashtbl.t
}
*)
type fn_ctxt = {
  uf: UnionFind.t;
  resolv: (int,typ) Hashtbl.t;
  (*  record_t: record_types;*)
  fenv: funenv;
  tyenv: tyenv
}

let make_fenv uf fns =
  List.fold_left (fun acc {name; args; _} ->
    StringMap.add name {
      arg_types_v = List.map (fun _ -> UnionFind.new_node uf) args;
      ret_type_v = UnionFind.new_node uf
    } acc) StringMap.empty fns

let init_tyenv fenv { name; args; _ } =
  let { arg_types_v; _ } = StringMap.find name fenv in
  List.fold_left2 (fun acc name var ->
    StringMap.add name (`Var var) acc) StringMap.empty args arg_types_v

let add_var v t ctxt =
  if StringMap.mem v ctxt.tyenv then
    failwith "variable shadowing"
  else
    { ctxt with tyenv = StringMap.add v t ctxt.tyenv }

let resolve_type uf resolv r =
  match r with
  | `Var v ->
    let id = UnionFind.find uf v in
    if Hashtbl.mem resolv id then
      (Hashtbl.find resolv id :> typ)
    else (`Var id)
  | _ -> r

let force_resolve uf resolv t : r_typ =
  match resolve_type uf resolv t with
  | `Int -> `Int
  | _ -> failwith "Unconstrained value"

let resolve ctxt (r: typ) =
  resolve_type ctxt.uf ctxt.resolv r

let rec unify ctxt t1 t2 =
  let ty_assign v ty = Hashtbl.add ctxt.resolv v ty in
  match (resolve ctxt t1, resolve ctxt t2) with
  | (`Var v1, `Var v2) -> UnionFind.union ctxt.uf v1 v2
  | (`Var v1, (#c_inst as ct))
  | (#c_inst as ct, `Var v1) ->
    ty_assign v1 ct
  | (`Ref t1',`Ref t2') ->
    unify ctxt t1' t2'
  | (`Tuple tl1, `Tuple tl2) ->
    List.iter2 (unify ctxt) tl1 tl2
  | (t1,t2) when t1 = t2 -> ()
  | _ -> failwith "Ill-typed"

let process_call lkp ctxt { callee; arg_names; _ } =
  let sorted_args = List.fast_sort Pervasives.compare arg_names in
  let rec find_dup l = match l with
    | [_]
    | [] -> false
    | h::h'::_ when h = h' -> true
    | _::t -> find_dup t
  in
  if find_dup sorted_args then
    failwith "Duplicate variable names detected"; 
  let { arg_types_v; ret_type_v } = StringMap.find callee ctxt.fenv in
  List.iter2 (fun a_var t_var ->
    unify ctxt (lkp a_var) @@ `Var t_var) arg_names arg_types_v;
  `Var ret_type_v

let rec process_expr ctxt e =
  let res t = resolve ctxt t in
  let lkp n = StringMap.find n ctxt.tyenv |> res in
  let unify_var n typ = unify ctxt (lkp n) typ in
  let unify_imm c = match c with
    | IInt _ -> ();
    | IVar v -> unify_var v `Int
  in
  let unify_ref v t =
    unify ctxt (lkp v) @@ `Ref t
  in
  let fresh_var () =
    let t = UnionFind.new_node ctxt.uf in
    `Var t
  in
  match e with
  | EVar v -> lkp v
  | Cond (_,v,e1,e2) ->
    unify_var v `Int;
    let t1 = process_expr ctxt e1 in
    let t2 = process_expr ctxt e2 in
    unify ctxt t1 t2; t1
  | Seq (e1,e2) ->
    process_expr ctxt e1 |> ignore;
    process_expr ctxt e2
  | Assign (v1,IInt _,e) ->
    unify_ref v1 `Int;
    process_expr ctxt e
  | Assign (v1,IVar v2,e) ->
    unify_ref v1 @@ lkp v2;
    process_expr ctxt e
  | Alias (_,v, ap,e) ->
    let rec find ap =
      match ap with
      | AVar v -> lkp v
      | ADeref ap ->
        let t = find ap in
        let tv = UnionFind.new_node ctxt.uf in
        unify ctxt t (`Ref (`Var tv));
        (`Var tv)
      | AProj (ap,ind) ->
        let t = find ap |> resolve ctxt in
        begin
        match t with
        | `Tuple tl when ind < List.length tl -> List.nth tl ind
        | _ -> failwith "Could not deduce length of tuple in alias"
        end
    in
    unify ctxt (lkp v) (find ap);
    process_expr ctxt e
  | Assert ({ rop1; rop2; _ },e) ->
    unify_imm rop1;
    unify_imm rop2;
    process_expr ctxt e
  | Let (_id,p,lhs,expr) ->
    let v_type =
      match lhs with
      | Var v -> lkp v
      | Const _ -> `Int
      | Mkref i -> begin
          match i with
          | RNone
          | RInt _ -> `Ref `Int
          | RVar v -> `Ref (lkp v)
        end
      | Call c -> process_call lkp ctxt c
      | Nondet -> `Int
      | Deref p ->
        let tv = fresh_var () in
        unify ctxt (`Ref tv) @@ lkp p;
        tv
      | Tuple tl ->
        `Tuple (List.map (function
          | RInt _
          | RNone -> `Int
          | RVar v -> lkp v
          ) tl)
    in
    let rec unify_patt acc p t =
      match p with
      | PVar v -> add_var v t acc
      | PNone -> acc
      | PTuple pl ->
        let (t_list,acc'') = List.fold_right (fun p (t_list,acc') ->
            let t_var = fresh_var () in
            (t_var::t_list,unify_patt acc' p t_var)
          ) pl ([], acc) in
        unify ctxt t (`Tuple t_list);
        acc''
    in
    let ctxt' = unify_patt ctxt p v_type in
    process_expr ctxt' expr

let constrain_fn uf fenv resolv ({ name; body; _ } as fn) =
  let tyenv = init_tyenv fenv fn in
  let ctxt =  { uf; fenv; tyenv; resolv } in
  let out_type = process_expr ctxt body in
  unify ctxt out_type (`Var (StringMap.find name fenv).ret_type_v)

let typecheck_prog _intr_types (fns,body) =
  (*let rec_ctxt = List.fold_left (fun ctxt {body; _ } ->
      compute_f body ctxt
    ) SM.empty fns
    |> compute_f body
  in*)
  let (resolv : (int,typ) Hashtbl.t) = Hashtbl.create 10 in
  let uf = UnionFind.mk (fun ~parent ~child ->
      if Hashtbl.mem resolv child then
        Hashtbl.add resolv parent (Hashtbl.find resolv child)
      else ()
    ) in
(*  let record_t =
    let rec_of_field = Hashtbl.create 10 in
    let fields_of_rec = Hashtbl.create 10 in
    let type_of_field = Hashtbl.create 10 in
    let i = ref 0 in
    SM.iter (fun _ ss ->
      let r_type = !i in
      incr i;
      SS.iter (fun field ->
        let v_type = UnionFind.new_node uf in
        Hashtbl.add rec_of_field field r_type;
        Hashtbl.add type_of_field field v_type;
      ) ss;
      Hashtbl.add fields_of_rec r_type ss
    ) rec_ctxt;
    { rec_of_field; fields_of_rec; type_of_field }
   in*)
  let fenv_ : funenv = make_fenv uf fns in
  let fenv =
    let _lift_type t =
      let n_id = UnionFind.new_node uf in
      Hashtbl.add resolv n_id t;
      n_id
    in
    (*StringMap.fold (fun k { arg_types; ret_type } ->
      StringMap.add k {
        arg_types_v = List.map lift_type arg_types;
        ret_type_v = lift_type ret_type;
      }
       ) intr_types fenv_*)
    fenv_
  in
  List.iter (constrain_fn uf fenv resolv) fns;
  process_expr {
    resolv; uf; fenv; tyenv = StringMap.empty;
  } body |> ignore;
  let get_soln = force_resolve uf resolv in
  List.fold_left (fun acc { name; _ } ->
    let { arg_types_v; ret_type_v } = StringMap.find name fenv in
    let arg_types = List.map get_soln @@ List.map (fun x -> `Var x) arg_types_v in
    let ret_type = get_soln @@ `Var ret_type_v in
    StringMap.add name { arg_types; ret_type } acc
  ) StringMap.empty fns
