# ConSORT with counterexample generation

# Requirements
This implementation is very fragile so it may not work if the verision of eldarica differs.
At least, it will work in the following setup
* Eldarica v2.0.3
* Z3 4.8.8

# Usage
```
$ cd src
# ownership slice
$ ./test_counterexample.sh cex-test/ownership_slice.imp
# trace
$ ./test_counterexample.sh cex-test/cex_gen_example.imp
$ ./test_coutnerexample.sh cex-test/result_list_example.imp
$ ./test_counterexample.sh cex-test/result_array_example.imp
# unsafe slice
$ ./test_counterexample.sh cex-test/unsafe_slice.imp 
```
Outputs exists in `cex-test/result/`
