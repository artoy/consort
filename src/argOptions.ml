module Solver = struct
  type choice =
    | Hoice
    | Spacer
    | Z3SMT
    | Eldarica
    | Parallel
    | Null
  type options = {
    timeout : int;
    command : string option;
    command_extra : string option;
  }

  let default = {
    timeout = 30;
    command = None;
    command_extra = None
  }

  let opt_gen ?nm ?(solv_nm="solver") () =
    let open Arg in
    let pref = Option.map (fun s -> s ^ "-") nm |> Option.value ~default:"" in
    let timeout = ref default.timeout in
    let command = ref None in
    let extra = ref None in
    let spec = [
      ("-" ^ pref ^ "timeout", Set_int timeout,
       Printf.sprintf "Timeout for %s in seconds" solv_nm);
      ("-" ^ pref ^ "command", String (fun s -> command := Some s),
       Printf.sprintf "Executable for %s" solv_nm);
      ("-" ^ pref ^ "solver-args", String (fun s -> extra := Some s),
       Printf.sprintf "Extra arguments to pass wholesale to %s" solv_nm)
    ] in
    let update ?(comb=default) () =
      let _ = comb in {
        timeout = !timeout;
        command = !command;
        command_extra = !extra
      } in
    (spec, update)
end

type t = {
  debug_cons : bool;
  debug_ast : bool;
  save_cons : string option;
  annot_infr : bool;
  print_model : bool;
  dry_run : bool;
  check_trivial : bool;
  solver : Solver.choice;
  dump_ir : string option;
  relaxed_mode : bool;
  omit_havoc : bool;
  null_checks : bool;
  solver_opts : Solver.options;
  own_solv_opts : Solver.options
}
type arg_spec = Arg.key * Arg.spec * Arg.doc
type arg_update = ?comb:t -> unit -> t
type arg_gen = arg_spec list * arg_update

let default = {
  debug_cons = false;
  debug_ast = false;
  save_cons = None;
  annot_infr = false;
  print_model = false;
  dry_run = false;
  check_trivial = false;
  solver = Spacer;
  dump_ir = None;
  relaxed_mode = false;
  omit_havoc = false;
  null_checks = false;
  solver_opts = Solver.default;
  own_solv_opts = Solver.default;
}
let spec_seq (g2 : unit -> arg_gen) (g1 : arg_gen) =
  let s1, f1 = g1 in
  let s2, f2 = g2 () in
  let spec = s1 @ s2 in
  let update ?(comb=default) () = f2 ~comb:(f1 ~comb ()) () in
  (spec, update)
let infr_opts_loader () =
  let relaxed_max = ref false in
  let open Arg in
  let spec = [
    ("-relaxed-max", Unit (fun () -> relaxed_max := true),
     "Use alternative, relaxed maximization constraints")
  ] in
  (spec, (fun () -> !relaxed_max))
let opt_gen () =
  let (spec, update) = Solver.opt_gen () in
  (spec, fun ?(comb=default) () -> {
        comb with
        solver_opts = update ~comb:comb.solver_opts ()
      })
let ownership_arg_gen () =
  let (spec, update) =
    Solver.opt_gen ~nm:"o" ~solv_nm:"ownership solver" () in
  (spec, fun ?(comb=default) () -> {
        comb with
        own_solv_opts = update ~comb:comb.own_solv_opts ()
      })
let solver_arg_gen () =
  let check_trivial = ref default.check_trivial in
  let solver = ref default.solver in
  let dump_ir = ref default.dump_ir in
  let omit_havoc = ref default.omit_havoc in
  let null_checks = ref default.null_checks in
  let oi_args,oi_gen = infr_opts_loader () in
  let open Arg in
  let spec = [
    ("-seq-solver", Unit (fun () ->
         prerr_endline "WARNING: seq solver option is deprecated and does nothing"),
     "(DEPRECATED) No effect");
    ("-check-triviality", Set check_trivial,
     "Check if produced model is trivial");
    ("-mode", Symbol (["refinement"; "unified"], fun _ ->
         prerr_endline "WARNING: the mode option is deprecated and does nothing"),
     " (DEPRECATED) No effect");
    ("-dump-ir", String (fun s -> dump_ir := Some s),
     "Dump intermediate relations and debugging information (only implemented in unified)");
    ("-omit-havoc", Set omit_havoc,
     "Omit havoced access paths from the generated CHC (implies relaxed-max) (EXPERIMENTAL)");
    ("-check-null", Set null_checks,
     "For freedom of null pointer exceptions");
    ("-solver",
     Symbol (["spacer";"hoice";"z3";"null";"eldarica";"parallel"], function
         | "spacer" -> solver := Spacer
         | "hoice" -> solver := Hoice
         | "null" -> solver := Null
         | "z3" -> solver := Z3SMT
         | "eldarica" -> solver := Eldarica
         | "parallel" -> solver := Parallel
         | _ -> assert false),
     " Use solver backend <solver>. (default: spacer)")
  ] in
  let update ?(comb=default) () = {
    comb with
    check_trivial = !check_trivial;
    solver = !solver;
    dump_ir = !dump_ir;
    relaxed_mode = oi_gen () || !omit_havoc;
    omit_havoc = !omit_havoc;
    null_checks = !null_checks
  } in
  (oi_args @ spec, update)
let solver_opt_gen () =
  ownership_arg_gen () |> spec_seq opt_gen
