# Oberon-0 compiler for a bytecode VM

This repository contains the source code of an Oberon-0 compiler for the virtual machine found in the book
[Programming Language Concepts](https://www.itu.dk/people/sestoft/plc/).

The main goal was to show an alternative way to write a compiler, so that the reader can compare the multi-pass functional
approach of the book with the single-pass imperative one of this repository.

## How to build

To build the compiler on Linux, you need a JVM >= 1.8 installed, with java in
the environment path.

[Download](https://github.com/lboasso/oberonc/releases) and unpack the latest
release of the *oberonc* compiler and set the `OBERON_BIN` environmental
variable to the `bin` folder of the *oberonc* distribution. For example on Linux
`export OBERON_BIN=~/oberonc-1.4/bin`.

By typing `make build` on the shell, the compiler will compile the Oberon-0
source code (including the virtual machine) and write the files in the
`out` folder.

To compile and run an example program with the Oberon-0 compiler just built, use
the appropriate make target. For example `make factorial` will compile
`examples/Factorial.Mod` with the Oberon-0 compiler and run it on the virtual machine.
The output will show the bytecode instructions and the result of computing the factorial of `8`.
```
$ make factorial
mkdir -p out/
java -cp ~/oberonc-1.4/bin oberonc out src/OSS.Mod src/OSG.Mod src/OSP.Mod
java -cp ~/oberonc-1.4/bin:out OSP examples/Factorial.Mod
---ASSEMBLY---
  0  LDARGS
  1  GOTO  45
  3  INCSP   1
  5  GETBP
  6  LDI
  7  IFNZRO  20
  9  GETBP
 10  CSTI   1
 12  ADD
 13  CSTI   1
 15  STI
 16  INCSP  -1
 18  GOTO  38
 20  GETBP
 21  CSTI   1
 23  ADD
 24  GETBP
 25  LDI
 26  CSTI   1
 28  SUB
 29  CALL   1   3
 32  GETBP
 33  LDI
 34  MUL
 35  STI
 36  INCSP  -1
 38  GETBP
 39  CSTI   1
 41  ADD
 42  LDI
 43  RET   2
 45  CSTI   8
 47  CALL   1   3
 50  PRINTI
 51  INCSP  -1
 53  STOP

---RUN---
40320
```
