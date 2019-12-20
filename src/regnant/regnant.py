#!/usr/bin/env python

import sys
import subprocess
import tempfile
import atexit, shutil, os
import argparse

def log_command(args, cmd):
    if args.verbose:
        import pipes
        print "executing:"," ".join([ pipes.quote(s) for s in cmd ])

def run_silently(cmd, **kwargs):
    with open("/dev/null", "w") as out:
        subprocess.check_call(cmd, stdout = out, stderr = subprocess.STDOUT, **kwargs)

def main(this_dir, args):
    parser = argparse.ArgumentParser()
    parser.add_argument("--work-dir")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--jar")
    parser.add_argument("--skip-build", action="store_true", default = False)
    parser.add_argument("--debug-trans", action="store_true", default = False)
    parser.add_argument("--src-dir")
    parser.add_argument("jdk8")
    parser.add_argument("entry_point")
    parser.add_argument("consort_args", nargs="*")
    args = parser.parse_args(args)
    cls = args.entry_point
    if args.src_dir is None and args.jar is None:
        print "Need at least source or jar"
        return 1

    if args.debug_trans:
        args.verbose = True

    if not args.skip_build:
        run_silently(["gradle", "installDist"], cwd = this_dir)

    if args.work_dir is None:
        work_dir = tempfile.mkdtemp()
        atexit.register(lambda: shutil.rmtree(work_dir))
    else:
        work_dir = args.work_dir

    if args.jar is None:
        assert args.src_dir is not None
        cls_dir = os.path.join(work_dir, "classes")
        if not os.path.exists(cls_dir):
            os.makedirs(cls_dir)

        source_file = cls.replace(".", "/") + ".java"

        compile_command = ["javac", "-g:lines,vars", "-source", "8", "-target", "8", "-d", cls_dir, args.src_dir + "/" + source_file]
        log_command(args, compile_command)
        print "compiling source java...",
        sys.stdout.flush()
        run_silently(compile_command)
        print "done"
    else:
        cls_dir = args.jar

    flags = os.path.join(work_dir, "control.sexp")
    data = os.path.join(work_dir, "mono.imp")

    regnant_options = "enabled:true,output:%s,flags:%s" % (data, flags)

    run_script = os.path.join(this_dir, "build/install/regnant/bin/regnant")

    rt_path = os.path.join(args.jdk8, "jre/lib/rt.jar")

    regnant_command = [
        run_script,
        "-f", "n", # no output
        "-no-bodies-for-excluded", # don't load the JCL (for now)
        "-w", # whole program mode
        "-p", "cg.spark", "on", # run points to analysis
#        "-p", "jb", "use-original-names:true", # try to make our names easier
        "-soot-class-path", cls_dir + ":" + rt_path, # where to find the test file
        "-p", "wjtp.regnant", regnant_options,
        cls # the class to run on
    ]

    log_command(args, regnant_command)
    if args.debug_trans:
        return subprocess.call(regnant_command)
    print "Translating java bytecode...",
    sys.stdout.flush()
    run_silently(regnant_command)
    print "done"
    
    print "Generating control flags...",
    sys.stdout.flush()
    intr_loc = os.path.join(work_dir, "java.intr")

    intr_command = [
        os.path.join(this_dir, "../_build/default/genFlags.exe"),
        os.path.join(this_dir, "../stdlib/lin.intr"),
        flags,
        intr_loc,
        "generated.smt"
    ]
    log_command(args, intr_command)
    run_silently(intr_command)
    print "done"
    
    print "Running ConSORT on translated program:"
    consort_cmd = [
        os.path.join(this_dir, "../_build/default/test.exe"),
        "-intrinsics", intr_loc,
        "-exit-status",
    ] + args.consort_args + [
        data
    ]
    log_command(args, consort_cmd)
    return subprocess.call(consort_cmd)

if __name__ == "__main__":
    sys.exit(main(os.path.realpath(os.path.dirname(sys.argv[0])), sys.argv[1:]))
