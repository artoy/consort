let run_test v_opts intr expect file =
  if expect <> (VerifyUtil.check_file ~opts:v_opts ?intrinsic_defn:intr file) then
    failwith @@
      if expect then file ^ " did not verify as expected"
      else file ^ " incorrectly verified"
  else
    ()

let () =
  let expect = ref true in
  let i = ref None in
  let (a_list,gen) = VerifyUtil.Options.solver_arg_gen () in
  let args = [
    ("-neg", Arg.Clear expect, "Expect typing failures");
    ("-pos", Arg.Set expect, "Expect typing success (default)");
    ("-cfa", Arg.Set_int KCFA.cfa, "k to use for k-cfa inference");
    ("-intrinsics", Arg.String (fun x -> i := Some x), "Load built in intrinsics from <file>")
  ] @ a_list in
  let dir_list = ref [] in
  Arg.parse args (fun x -> dir_list := x::!dir_list) "Check folders for expected typing failures/success";
  let v_opts = gen () in
  List.iter (fun dir -> 
    let test_files = Sys.readdir dir in
    Array.iter (fun f_name ->
      if Filename.check_suffix f_name ".imp" then
        try
          run_test v_opts !i !expect (dir ^ "/" ^ f_name)
        with
          Failure s -> failwith @@ Printf.sprintf "Test %s failed with message: %s" f_name s
      else ()
    ) test_files;
  ) !dir_list;
  print_endline "PASSED"
