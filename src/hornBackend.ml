module Backend = Z3BasedBackend.Make(struct
    let z3_tactic = "(check-sat-using (then propagate-values qe-light horn))"
  end)

let solve = Backend.solve
