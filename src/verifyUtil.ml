open Std

let pprint_ty_env =
  let open PrettyPrint in
  fun ty_envs i ->
    let ty_env = Hashtbl.find ty_envs i in
    if (StringMap.cardinal ty_env) = 0 then
      pl [ ps "/* empty */"; newline ]
    else
      let pp_ty_env = StringMap.bindings ty_env
        |> List.map (fun (k,t) ->
            pb [
              pf "%s: " k;
              RefinementTypes.pp_type t
            ]
          )
        |> psep_gen newline
      in
      pblock ~nl:true ~op:(ps "/*") ~body:pp_ty_env ~close:(ps "*/")

module Options = struct
  type t = {
    debug_pred: bool;
    debug_cons: bool;
    debug_ast: bool;
    save_cons: string option;
    annot_infr: bool;
    print_model: bool;
    seq_solver: bool;
    check_trivial: bool
  }

  type arg_spec = (string * Arg.spec * string) list * (?comb:t -> unit -> t)

  let default = {
    debug_pred = false;
    debug_cons = false;
    save_cons = None;
    debug_ast = false;
    annot_infr = false;
    print_model = false;
    seq_solver = false;
    check_trivial = false
  }

  let debug_arg_gen () =
    let open Arg in
    let debug_cons = ref false in
    let debug_pred = ref false in
    let debug_ast = ref true in
    let show_model = ref false in
    let annot_infr = ref false in
    let save_cons = ref None in
    let all_debug_flags = [ debug_cons; debug_pred; debug_ast; show_model ] in
    let mk_arg key flg what =
      [
        ("-no-" ^ key, Clear flg, Printf.sprintf "Do not print %s" what);
        ("-show-" ^key, Set flg, Printf.sprintf "Print %s on stderr" what)
      ] in
    let arg_defs =
      (mk_arg "cons" debug_cons "constraints sent to Z3") @
        (mk_arg "ast" debug_ast "(low-level) AST") @
        (mk_arg "pred" debug_pred "predicate explanations") @
        (mk_arg "model" show_model "inferred model") @
        [
          ("-annot-infer", Set annot_infr, "Print an annotated AST program with the inferred types on stderr");
          ("-show-model", Set show_model, "Print model produced from successful verification");
          ("-save-cons", String (fun r -> save_cons := Some r), "Save constraints in <file>");
          ("-show-all", Unit (fun () ->
             List.iter (fun r -> r := true) all_debug_flags
           ), "Show all debug output");
          ("-none", Unit (fun () ->
             List.iter (fun r -> r:= false) all_debug_flags
           ), "Suppress all debug output")
        ] in
    (arg_defs, (fun ?(comb=default) () ->
       { comb with
         debug_pred = !debug_pred;
         debug_ast = !debug_ast;
         print_model = !show_model;
         annot_infr = !annot_infr;
         debug_cons = !debug_cons;
         save_cons = !save_cons
       }))

  let (>>) ((a1,f1) : arg_spec) ((a2,f2) : arg_spec) =
    (a1 @ a2, (fun ?(comb=default) () ->
       f2 ~comb:(f1 ~comb ()) ()))

  let seq f o =
    (o >> f ())

  let solver_arg_gen () =
    let open Arg in
    let seq_run = ref false in
    let check_trivial = ref false in    
    ([
      ("-seq-solver", Set seq_run, "Run two inference passes; the first inferring ownership, the second inferring refinements");
      ("-check-triviality", Set check_trivial, "Check if produced model is trivial")
    ], (fun ?(comb=default) () ->
       { comb with
         seq_solver = !seq_run;
         check_trivial = !check_trivial
       }))
end

let infer opts intr simple_res ast =
  if (not opts.Options.seq_solver) then
    Inference.infer ~print_pred:opts.debug_pred ~save_types:opts.annot_infr ~intrinsics:intr.Intrinsics.op_interp simple_res ast
    |> Option.return
  else
    let r = Inference.infer ~print_pred:false ~save_types:true ~intrinsics:intr.Intrinsics.op_interp simple_res ast in
    let module R = Inference.Result in
    match OwnershipSolver.solve_ownership r.R.theta r.R.ovars r.R.ownership with
    | None -> None
    | Some o_soln ->
      let open RefinementTypes in
      let module IM = Map.Make(struct type t = int let compare = (-) end) in
      let o_map = List.fold_left (fun acc (k,v) -> IM.add k v acc) IM.empty o_soln in
      let rec map_type =
        function
        | Int _ -> Int ()
        | Ref (t,OConst o,n) -> Ref (map_type t, o,n)
        | Ref (t,OVar ov,n) -> Ref (map_type t,IM.find ov o_map,n)
        | Tuple (_,tl) -> Tuple ([],List.map map_type tl)
        | TVar id -> TVar id
        | Mu (a,i,t) -> Mu (a,i,map_type t)
      in
      let o_gamma_tbl = Hashtbl.create 10 in
      Hashtbl.iter (fun i g ->
        Hashtbl.add o_gamma_tbl i @@ StringMap.map map_type g
      ) r.R.ty_envs;
      let o_theta = StringMap.map (fun { arg_types; output_types; result_type } ->
          {
            arg_types = List.map map_type arg_types;
            output_types = List.map map_type output_types;
            result_type = map_type result_type
          }) r.R.theta in
      Inference.infer
        ~print_pred:opts.debug_pred
        ~save_types:opts.annot_infr
        ~o_solve:(o_gamma_tbl,o_theta)
        ~intrinsics:intr.Intrinsics.op_interp
        simple_res ast
      |> Option.return

let check_triviality t =
  let check_model m_raw =
    let open Sexplib.Sexp in
    let m = of_string m_raw in
    match m with
    | List (Atom "model"::l) ->
      let triv_preds = List.fold_left (fun acc sexp ->
          match sexp with
          | List (Atom "define-fun"::Atom nm::rem) -> begin
            let rem_len = List.length rem in
            let final = List.nth rem @@ rem_len - 1 in
            match final with
            | Atom "false" -> nm::acc
            | _ -> acc
            end
          | _ -> acc
        ) [] l
      in
      if List.length triv_preds = 0 then
        ()
      else
        let bad_preds = String.concat ", " triv_preds in
        failwith @@ Printf.sprintf "Solution contains trivial solutions for %s" bad_preds
    | _ -> ()
  in
  if (not t) then Option.iter (fun _ -> ())
  else
    Option.iter check_model

let print_model t =
  if t then
    Option.iter (fun s -> prerr_endline s; flush stderr)
  else
    Option.iter (fun _ -> ())

let check_file ?(opts=Options.default) ?(intrinsic_defn=Intrinsics.empty) in_name =
  let open Options in
  let ast = AstUtil.parse_file in_name in
  let intr = intrinsic_defn in
  let simple_typing = RefinementTypes.to_simple_funenv intr.Intrinsics.op_interp in
  let ((program_types,_,_) as simple_res)= SimpleChecker.typecheck_prog simple_typing ast in
  if opts.debug_ast then begin
    AstPrinter.pretty_print_program stderr ast;
    StringMap.iter (fun n a ->
      Printf.fprintf stderr "%s: %s\n" n @@ SimpleTypes.fntype_to_string a
    ) program_types;
    flush stderr
  end;
  let r_opt = infer opts intr simple_res ast in
  match r_opt with
  | None -> false
  | Some r ->
    if opts.annot_infr then begin
      let ty_envs = r.Inference.Result.ty_envs in
      AstPrinter.pretty_print_program ~with_labels:true ~annot:(pprint_ty_env ty_envs) stderr ast;
      flush stderr
    end;
    let res =
      HornBackend.solve
        ~debug_cons:opts.debug_cons
        ?save_cons:opts.save_cons
        ~get_model:(opts.print_model || opts.check_trivial)
        ~interp:(intr.Intrinsics.rel_interp,intr.Intrinsics.def_file) r
    in
    match res with
    | Sat m ->
      check_triviality opts.check_trivial m;
      print_model opts.print_model m;
      true
    | _ -> false
