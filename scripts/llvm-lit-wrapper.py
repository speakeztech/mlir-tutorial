#!/usr/bin/env python3
"""
Wrapper script to invoke lit module when llvm-lit executable is not available.
This is needed for MSYS2 CLANG64 where lit is installed via pip but not included in LLVM.
"""
import sys
import runpy

if __name__ == '__main__':
    sys.argv[0] = 'lit'
    runpy.run_module('lit.main', run_name='__main__')
