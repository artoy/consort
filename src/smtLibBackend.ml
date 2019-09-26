module type STRATEGY = sig
  val solve: Solver.solve_fn
end

type intrinsic_interp  = (string StringMap.t) * string option
type solver_intf = (interp:intrinsic_interp -> Inference.Result.t -> Solver.result) Solver.option_fn
module Make(S: STRATEGY) : sig
  val solve : solver_intf
end = struct
  open SexpPrinter
  open Inference
  open RefinementTypes
  open Std.StateMonad
  open Std

  let pred_name p = p

  let pp_imm o ff = match o with
    | RAp ap -> atom ff @@ Paths.to_z3_ident ap
    | RConst i -> atom ff @@ string_of_int i

  let pp_relop ?nu r ff = match nu,r with
    | Some binding,Nu -> atom ff binding
    | _,RImm ri -> pp_imm ri ff
    | None,_ -> failwith "Malformed constraint: did not bind a target for nu"

  let refine_args _ l = List.map Paths.to_z3_ident l

  let ctxt_var i = "CTXT" ^ (string_of_int i)

  let string_of_nullity = function
    | `NNull -> "false"
    | `NLive -> "true"
    | `NVar v -> v

  let rec pp_refine ~nullity ~interp ?nu r ff =
    let binding_opt = Option.map Paths.to_z3_ident nu in
    match binding_opt,r with
    | Some binding,NamedPred (n,(args,o)) ->
      ff |> psl @@ [ n; binding ] @ (refine_args o args)
    | Some binding,Pred (i,(args,o)) ->
      let ctxt = List.init !KCFA.cfa ctxt_var in
      print_string_list (pred_name i::ctxt @ [ binding ] @ (refine_args o args) @ [ string_of_nullity nullity ]) ff
    | Some binding,CtxtPred (ctxt,i,(args,o)) ->
      let c_string =
        if !KCFA.cfa > 0 then
          (string_of_int ctxt)::(List.init (!KCFA.cfa-1) (fun i -> ctxt_var @@ i))
        else
          []
      in
      print_string_list (pred_name i::c_string @ [ binding ] @ (refine_args o args) @ [ string_of_nullity nullity ]) ff
    | _,Top -> atom ff "true"
    | Some binding,ConstEq n -> print_string_list [ "="; binding; string_of_int n ] ff
    | _,Relation { rel_op1; rel_cond = cond_name; rel_op2 } ->
      let intr = StringMap.find cond_name interp in
      pg intr [
        pp_relop ?nu:binding_opt rel_op1;
        pp_imm rel_op2
      ] ff
    | _,And (r1,r2) ->
      pg "and" [
          pp_refine ~nullity ~interp ?nu r1;
          pp_refine ~nullity ~interp ?nu r2
        ] ff
    | None,(CtxtPred _ | NamedPred _ | Pred _ | ConstEq _) ->
      failwith "Malformed refinement: expect a nu binder but none was provided"
        
  let close_env env ante conseq =
    let module SS = Std.StringSet in
    let update acc =
      fold_refinement_args ~rel_arg:(fun ss a ->
        SS.add (Paths.to_z3_ident a) ss
      ) ~pred_arg:(fun acc (a,_) ->
        List.fold_left (fun acc p ->
          SS.add (Paths.to_z3_ident p) acc
        ) acc a
      ) acc
    in
    let const_paths = List.fold_left (fun acc (p,_,_) ->
        if Paths.is_const_ap p then
          SS.add (Paths.to_z3_ident p) acc
        else acc) SS.empty env
    in
    let seed = update (update const_paths ante) conseq in
    let rec fixpoint acc =
      let acc' = List.fold_left (fun acc (a,p,_) ->
          let id = Paths.to_z3_ident a in
          if SS.mem id acc then
            update acc p
          else
            acc
        ) acc env in
      if (SS.cardinal acc) = (SS.cardinal acc') then
        acc'
      else
        fixpoint acc'
    in
    let closed_names = fixpoint seed in
    List.filter (fun (k,_,_) ->
      SS.mem (Paths.to_z3_ident k) closed_names
    ) env

  let simplify sexpr =
    let open Sexplib.Sexp in
    (fun k ->
      let rec simplify_loop acc r =
        match r with
        | List (Atom "and"::rest) ->
          List.fold_left simplify_loop acc rest
        | Atom "true" -> acc
        | _ -> r::acc
      in
      match simplify_loop [] sexpr with
      | [] -> k @@ Atom "true"
      | [h] -> k h
      | l -> k @@ List (Atom "and"::l)
    )

  let to_atomic_preds =
    let rec loop acc = function
      | And (r1,r2) -> loop (loop acc r1) r2
      | r -> r::acc
    in
    loop []

  type smt_nullity = [
    | `NVar of string
    | `NLive
    | `NNull
  ]

  module NullityOrd = struct
    type key = smt_nullity
    type t = key
    let compare = compare
  end

  module NullityMap = Map.Make(NullityOrd)
  module NullitySet = Set.Make(NullityOrd)

  let lift_nullity = function
    | `NLive -> return `NLive
    | `NNull -> return @@ `NNull
    | `NVar i ->
      let nm = Printf.sprintf "bool?%d" i in
      let%bind () = mutate @@ (fun (im,vs) -> (im,StringSet.add nm vs)) in
      return @@ `NVar nm

  let lift_nullity_chain nl =
    match nl with
    | [] -> return @@ `NLive
    | [h] -> lift_nullity h
    | h::t ->
      let%bind lh = lift_nullity h in
      let rec impl_loop curr rem =
        match rem with
        | [] -> return lh
        | h'::t ->
          let%bind lh' = lift_nullity h' in
          let%bind () = mutate @@ (fun (impl,vs) ->
              let impl' = NullityMap.update curr (function
              | None -> Some (NullitySet.singleton lh')
              | Some s -> Some (NullitySet.add lh' s)
                ) impl
              in
              (impl',vs)
            ) in
          impl_loop lh' t
      in
      impl_loop lh t

  let pp_constraint ~interp ff { env; ante; conseq; nullity; target } =     
    let gamma = close_env env ante conseq in
    let context_vars = List.init !KCFA.cfa (fun i -> Printf.sprintf "(%s Int)" @@ ctxt_var i) in
    let env_vars =
      List.fold_left (fun acc (ap,_,_) -> StringSet.add (Paths.to_z3_ident ap) acc) StringSet.empty gamma
      |> Option.fold ~none:(Fun.id) ~some:(fun p -> StringSet.add (Paths.to_z3_ident p)) target
    in
    do_with_context (NullityMap.empty,StringSet.empty) @@
      let%bind denote_gamma = mmap (fun (p,r,nl) ->
          let%bind n' = lift_nullity_chain nl in
          return @@ pp_refine ~nullity:n' ~nu:p ~interp r
        ) gamma
      in
      let%bind pred_nullity = lift_nullity_chain nullity in
      let%bind (nullity_ante,b_vars) = get_state in
      let null_args = List.map (Printf.sprintf "(%s Bool)") @@ StringSet.elements b_vars in
      
      let nullity_assume =
        NullityMap.fold (fun src dst_set acc1 ->
          NullitySet.fold (fun dst acc2 ->
            (pg "=>" [
               pl @@ string_of_nullity src;
               pl @@ string_of_nullity dst
             ])::acc2
          ) dst_set acc1
        ) nullity_ante [] in
      let e_assum = nullity_assume @ denote_gamma in
      let free_vars = StringSet.fold (fun nm acc ->
          (Printf.sprintf "(%s Int)" nm)::acc
        ) env_vars @@ context_vars @ null_args
      in
      let atomic_preds = to_atomic_preds conseq in
      return @@ List.iter (fun atomic_conseq ->
          pg "assert" [
            pg "forall" [
              print_string_list free_vars;
              pg "=>" [
                pg "and" ((pp_refine ~nullity:pred_nullity ~interp ante ?nu:target)::e_assum) simplify;
                pp_refine ~nullity:pred_nullity ~interp atomic_conseq ?nu:target
              ]
            ]
          ] ff.printer;
          break ff
        ) atomic_preds

  let solve ~opts ~debug_cons ?save_cons ~get_model ~interp:(interp,defn_file) infer_res =
    let ff = SexpPrinter.fresh () in
    let open Inference.Result in
    let { refinements; arity; _ } = infer_res in
    StringMap.iter (fun k (ground,v) ->
      pg "declare-fun" [
        pl @@ pred_name k;
        psl @@ (List.init v (fun _ -> "Int")) @ [ "Bool" ];
        pl "Bool";
      ] ff.printer;
      break ff;
      begin
        if ground then
          let g_name = Printf.sprintf "!g%d" in
          pg "assert" [
            pg "forall" [
              ll @@ List.init v (fun i -> psl [ g_name i; "Int"]);
              pg (pred_name k) @@ (List.init v (fun i -> pl @@ g_name i)) @ [
                pl "false"
              ]
            ]
          ] ff.printer;
          break ff
          
      end;
    ) arity;
    List.iter (pp_constraint ~interp ff) refinements;
    SexpPrinter.finish ff;
    S.solve ~opts ~debug_cons ?save_cons ~get_model ~defn_file ff
end
