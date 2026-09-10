"""Run a dependency-free Ruby check using a game's bundled Ruby DLL on Windows.

This runtime has no installed gems; use a normal Ruby installation for test/unit.
The check runs in a separate process and Ruby exceptions return a nonzero exit code.
"""
import argparse
import ctypes
import json
import os
from pathlib import Path
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("script", type=Path)
    parser.add_argument("--game", type=Path, required=True)
    args = parser.parse_args()
    game = args.game.resolve()
    with os.add_dll_directory(str(game)):
        ruby = ctypes.CDLL(str(game / "x64-msvcrt-ruby300.dll"))
        if ruby.ruby_setup() != 0:
            raise RuntimeError("Ruby initialization failed")
        # ruby_options loads Ruby's built-in prelude (Object#clone, etc.).
        ruby.ruby_options.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_char_p)]
        ruby.ruby_options.restype = ctypes.c_void_p
        argv = (ctypes.c_char_p * 4)(b"ruby", b"--disable-gems", b"-e", b"")
        ruby.ruby_options(4, argv)
        ruby.rb_eval_string_protect.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_int)]
        ruby.rb_eval_string_protect.restype = ctypes.c_size_t
        with tempfile.TemporaryDirectory(prefix="portable-ruby-") as temp:
            report = Path(temp) / "result.txt"
            source = ("begin; load " + json.dumps(args.script.resolve().as_posix()) +
                      "; File.write(" + json.dumps(report.as_posix()) + ', "PASS");' +
                      " rescue Exception => e; File.write(" + json.dumps(report.as_posix()) +
                      ', e.full_message); end')
            status = ctypes.c_int()
            ruby.rb_eval_string_protect(source.encode(), ctypes.byref(status))
            result = report.read_text(encoding="utf-8") if report.exists() else "Ruby failed without report"
            print(result)
            return 0 if status.value == 0 and result == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
