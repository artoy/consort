type reason =
  | Timeout
  | Unsafe
  | UnhandledSolverOutput of string
  | SolverError of string
  | Aliasing
  | Unknown

type check_result =
  | Verified
  | Unverified of reason

let reason_to_string reason with_msg =
  match reason with
  | Timeout -> "timeout"
  | Unsafe -> "unsafe"
  | UnhandledSolverOutput s ->
    if with_msg then
      Printf.sprintf "unhandled solver output: \"%s\"" s
    else "unhandled"
  | SolverError s ->
    if with_msg then
      Printf.sprintf "solver: \"%s\"" s
    else "solver-error"
  | Aliasing -> "ownership"
  | Unknown -> "unknown"

let result_to_string = function
  | Verified -> "VERIFIED"
  | Unverified r -> Printf.sprintf "UNVERIFIED (%s)" @@ reason_to_string r true

let choose_solver opts =
  match opts.ArgOptions.solver with
  | Eldarica -> EldaricaBackend.solve
  | Hoice -> HoiceBackend.solve
  | Null -> NullSolver.solve
  | Parallel -> ParallelBackend.solve
  | Spacer -> HornBackend.solve
  | Z3SMT -> SmtBackend.solve

let to_hint o_res record =
  let open OwnershipSolver in
  let open OwnershipInference in
  let o_map = function
    | OVar v -> List.assoc v o_res
    | OConst c -> c in
  let s_map (a, b) = o_map a, o_map b in
  {
    splits = SplitMap.map s_map record.splits;
    gen = GenMap.map o_map record.gen
  }

let consort ~opts file =
  let ast = AstUtil.parse_file file in
  let intr_op = (ArgOptions.get_intr opts).op_interp in
  let simple_typing = RefinementTypes.to_simple_funenv intr_op in
  let simple_res = SimpleChecker.typecheck_prog simple_typing ast in
  let infer_res = OwnershipInference.infer ~opts simple_res ast in
  let ownership_res = OwnershipSolver.solve_ownership ~opts (
      infer_res.ovars, infer_res.ocons, infer_res.max_vars) in
  match ownership_res with
  | None -> Unverified Aliasing
  | Some o_res ->
    let o_hint = to_hint o_res infer_res.op_record in
    let module Backend = struct
      let solve = choose_solver opts
    end in
    let module S = FlowBackend.Make(Backend) in
    let ans = S.solve ~opts simple_res o_hint ast in
    match ans with
    | Sat _ -> Verified
    | Unsat -> Unverified Unsafe
    | Timeout -> Unverified Timeout
    | Unhandled msg -> Unverified (UnhandledSolverOutput msg)
    | Error s -> Unverified (SolverError s)
    | Unknown -> Unverified Unknown
