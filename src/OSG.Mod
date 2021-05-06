(*
  Copyright 2021 Luca Boasso. All rights reserved.
  Use of this source code is governed by a MIT
  license that can be found in the LICENSE file.
*)

(* Code generator *)
MODULE OSG;
  IMPORT OSS, Out;

  CONST MemSize = 2000;
    (* class / mode*) Head* = 0;
    Const* = 1; Var* = 2; Par* = 3; Fld* = 4; Typ* = 5;
    SProc* = 6; SFunc* = 7; Proc* = 8; NoTyp* = 9; Stack = 10; Indirect = 11;
    Cond = 12;

    (* form *) Boolean* = 0; Integer* = 1; Array* = 2; Record* = 3;

    (*opcodes*)
    CSTI = 0; ADD = 1; SUB = 2; MUL = 3; DIVx = 4; MODx = 5;
    EQ = 6; LT = 7; NOT = 8;
    DUP = 9; SWAP = 10;
    LDI = 11; STI = 12;
    GETBP = 13; GETSP = 14; INCSP = 15;
    GOTO = 16; IFZERO = 17; IFNZRO = 18; CALL = 19; TCALL = 20; RET = 21;
    PRINTI = 22; PRINTC = 23;
    LDARGS = 24;
    STOP = 25;

  TYPE Object* = POINTER TO ObjDesc;
    Type* = POINTER TO TypeDesc;

    Item* = RECORD
      mode*: INTEGER;
      type*: Type;
      a*, b, r: INTEGER
    END ;

    ObjDesc*= RECORD
      class*, lev*: INTEGER;
      next*, dsc*: Object;
      type*: Type;
      name*: OSS.Ident;
      val*: INTEGER
    END ;

    TypeDesc* = RECORD
      form*: INTEGER;
      dsc*: Object;
      base*: Type;
      size*, len*, nofpar*: INTEGER
    END ;

  VAR boolType*, intType*, noType*: Type;
    pc*, globalDataSize: INTEGER;
    code*: ARRAY MemSize OF INTEGER;

  PROCEDURE Put0(op: INTEGER);
  BEGIN (*emit format-0 instruction*)
    code[pc] := op; INC(pc)
  END Put0;

  PROCEDURE Put1(op, a: INTEGER);
  BEGIN (*emit format-1 instruction*)
    code[pc] := op;
    code[pc+1] := a;
    INC(pc, 2)
  END Put1;

  PROCEDURE Put2(op, a, b: INTEGER);
  BEGIN
    code[pc] := op;
    code[pc+1] := a;
    code[pc+2] := b;
    INC(pc, 3)
  END Put2;


  PROCEDURE SetCC(VAR x: Item; n: INTEGER);
  BEGIN x.mode := Cond; x.a := 0; x.b := 0; x.r := n
  END SetCC;

  PROCEDURE negated(op: INTEGER): INTEGER;
  BEGIN
    IF op = IFZERO THEN op := IFNZRO ELSE op := IFZERO END ;
    RETURN op
  END negated;

  PROCEDURE fix(at, with: INTEGER);
  BEGIN code[at+1] := with
  END fix;

  PROCEDURE FixLinkWith*(L0, dst: INTEGER);
    VAR L1: INTEGER;
  BEGIN
    WHILE (L0 # 0) & (L0 < MemSize) & (OSS.errcnt = 0) DO
      L1 := code[L0+1]; fix(L0, dst); L0 := L1
    END
  END FixLinkWith;

  PROCEDURE FixLink*(L: INTEGER);
  BEGIN  FixLinkWith(L, pc)
  END FixLink;

  PROCEDURE addOffset(x: INTEGER);
  BEGIN
    IF x > 0 THEN
      Put1(CSTI, x);
      Put0(ADD)
    END
  END addOffset;

  PROCEDURE localAddr(a: INTEGER);
  BEGIN
    Put0(GETBP);
    addOffset(a)
  END localAddr;

  PROCEDURE load(VAR x: Item);
    VAR L0, L1: INTEGER;
  BEGIN
    IF x.mode # Stack THEN
      IF x.mode = Var THEN
        IF x.r > 0 THEN (*local*)
          localAddr(x.a)
        ELSE Put1(CSTI, x.a) END ;
        Put0(LDI);
      ELSIF x.mode = Par THEN
       localAddr(x.a);
        Put0(LDI);
        addOffset(x.b);
        Put0(LDI)
      ELSIF x.mode = Const THEN
        Put1(CSTI, x.a)
      ELSIF x.mode = Indirect THEN
        addOffset(x.a);
        Put0(LDI)
      ELSIF x.mode = Cond THEN
        L0 := pc;
        Put1(negated(x.r), 0);
        FixLink(x.b); Put1(CSTI, 1);
        L1 := pc;
        Put1(GOTO, 0);
        FixLink(x.a);
        FixLink(L0);
        Put1(CSTI, 0);
        FixLink(L1)
      END ;
      x.mode := Stack
    END
  END load;

  PROCEDURE loadAdr(VAR x: Item);
  BEGIN
    IF x.mode = Var THEN
      IF x.r > 0 THEN (*local*)
        localAddr(x.a)
      ELSE Put1(CSTI, x.a) END ;
    ELSIF x.mode = Par THEN
      localAddr(x.a);
      Put0(LDI);
      addOffset(x.b)
    ELSIF x.mode = Indirect THEN addOffset(x.a)
    ELSE OSS.Mark("address error")
    END
  END loadAdr;

  PROCEDURE loadCond(VAR x: Item);
  BEGIN
    IF x.type.form = Boolean THEN
      load(x); x.r := IFNZRO;
      x.mode := Cond; x.a := 0; x.b := 0
    ELSE OSS.Mark("not Boolean")
    END
  END loadCond;

  PROCEDURE loadAndMaybeSwap(VAR x, y: Item);
  BEGIN
    IF (x.mode = Const) & (y.mode # Const) THEN
      (*x loading has been delayed, so fully load y and restore the order
        (SWAP)*)
      load(y);
      load(x);
      Put0(SWAP)
    ELSE load(x); load(y)
    END
  END loadAndMaybeSwap;

  PROCEDURE loadOp0*(VAR x: Item);
  BEGIN
    load(x)
  END loadOp0;

  PROCEDURE loadOp*(VAR x: Item);
  BEGIN
    IF x.mode # Const THEN
      load(x)
    END
  END loadOp;

  PROCEDURE merged(L0, L1: INTEGER): INTEGER;
    VAR L2, L3: INTEGER;
  BEGIN
    IF L0 # 0 THEN
      L3 := L0;
      REPEAT L2 := L3; L3 := code[L2 + 1] UNTIL L3 = 0;
      fix(L2, L1); L1 := L0
    END ;
    RETURN L1
  END merged;

  (*-----------------------------------------------*)

  PROCEDURE MakeConstItem*(VAR x: Item; typ: Type; val: INTEGER);
  BEGIN x.mode := Const; x.type := typ; x.a := val
  END MakeConstItem;

  PROCEDURE MakeItem*(VAR x: Item; y: Object; curlev: INTEGER);
  BEGIN x.mode := y.class; x.type := y.type; x.a := y.val;
    IF y.class = Par THEN x.b := 0
    ELSE x.r := y.lev END ;
    IF (y.lev > 0) & (y.lev # curlev) & (y.class # Const) THEN OSS.Mark("level error") END
  END MakeItem;

  PROCEDURE Field*(VAR x: Item; y: Object);   (* x := x.y *)
  BEGIN
    IF (x.mode = Var) OR (x.mode = Indirect) THEN x.a := x.a + y.val
    ELSIF x.mode = Par THEN x.b := x.b + y.val
    END
  END Field;

  PROCEDURE Index*(VAR x, y: Item);   (* x := x[y] *)
    VAR s: INTEGER;
  BEGIN
    s := x.type.base.size;
    IF y.mode = Const THEN
      IF (y.a < 0) OR (y.a >= x.type.len) THEN OSS.Mark("bad index") END ;
      IF x.mode = Par THEN x.b := x.b + y.a * s
      ELSE x.a := x.a + y.a * s END ;
    ELSE
      load(y);
      IF s > 1 THEN Put1(CSTI, s); Put0(MUL) END ;
      IF x.mode = Var THEN
        IF x.r > 0 THEN Put0(GETBP); Put0(ADD) END ;
        x.mode := Indirect
      ELSIF x.mode = Par THEN
        localAddr(x.a);
        Put0(LDI);
        Put0(ADD);
        x.mode := Indirect; x.a := x.b
      ELSIF x.mode = Indirect THEN Put0(ADD)
      END
    END
  END Index;

  (* Code generation for Boolean operators *)

  PROCEDURE Not*(VAR x: Item);   (* x := ~x *)
    VAR t: INTEGER;
  BEGIN
    IF x.mode # Cond THEN loadCond(x) END ;
    x.r := negated(x.r); t := x.a; x.a := x.b; x.b := t
  END Not;

  PROCEDURE And1*(VAR x: Item);   (* x := x & *)
    VAR L0: INTEGER;
  BEGIN
    IF x.mode # Cond THEN loadCond(x) END ;
    L0 := pc;
    Put1(negated(x.r), x.a); x.a := L0; FixLink(x.b); x.b := 0
  END And1;

  PROCEDURE And2*(VAR x, y: Item);
  BEGIN
    IF y.mode # Cond THEN loadCond(y) END ;
    x.a := merged(y.a, x.a); x.b := y.b; x.r := y.r
  END And2;

  PROCEDURE Or1*(VAR x: Item);   (* x := x OR *)
    VAR L0: INTEGER;
  BEGIN
    IF x.mode # Cond THEN loadCond(x) END ;
    L0 := pc;
    Put1(x.r, x.b); x.b := L0; FixLink(x.a); x.a := 0
  END Or1;

  PROCEDURE Or2*(VAR x, y: Item);
  BEGIN
    IF y.mode # Cond THEN loadCond(y) END ;
    x.a := y.a; x.b := merged(y.b, x.b); x.r := y.r
  END Or2;

  (* Code generation for arithmetic operators *)

  PROCEDURE Neg*(VAR x: Item);   (* x := -x *)
  BEGIN
    IF x.mode = Const THEN x.a := -x.a
    ELSE Put1(CSTI, 0); load(x); Put0(SUB)
    END
  END Neg;

  PROCEDURE AddOp*(op: INTEGER; VAR x, y: Item);   (* x := x +- y *)
  BEGIN
    IF op = OSS.plus THEN
      IF (x.mode = Const) & (y.mode = Const) THEN x.a := x.a + y.a
      ELSIF y.mode = Const THEN load(x);
        IF y.a # 0 THEN load(y);  Put0(ADD) END
      ELSE loadAndMaybeSwap(x, y); Put0(ADD)
      END
    ELSE (*op = OSS.minus*)
      IF (x.mode = Const) & (y.mode = Const) THEN x.a := x.a - y.a
      ELSIF y.mode = Const THEN load(x);
        IF y.a # 0 THEN load(y); Put0(SUB) END
      ELSE loadAndMaybeSwap(x, y); Put0(SUB)
      END
    END
  END AddOp;

  PROCEDURE MulOp*(VAR x, y: Item);   (* x := x * y *)
  BEGIN
    IF (x.mode = Const) & (y.mode = Const) THEN x.a := x.a * y.a
    ELSIF y.mode = Const THEN
      load(x);
      IF y.a # 1 THEN load(y); Put0(MUL) END ;
    ELSE loadAndMaybeSwap(x, y); Put0(MUL)
    END
  END MulOp;

  PROCEDURE DivOp*(op: INTEGER; VAR x, y: Item);   (* x := x op y *)
  BEGIN
    IF op = OSS.div THEN
      IF (x.mode = Const) & (y.mode = Const) THEN
        IF y.a > 0 THEN x.a := x.a DIV y.a ELSE OSS.Mark("bad divisor") END
      ELSIF y.mode = Const THEN
        IF y.a > 0 THEN
          load(x);
          IF y.a # 1 THEN load(y); Put0(DIVx) END ;
        ELSE OSS.Mark("bad divisor")
        END
      ELSE loadAndMaybeSwap(x, y); Put0(DIVx)
      END
    ELSE (*op = OSS.mod*)
      IF (x.mode = Const) & (y.mode = Const) THEN
        IF y.a > 0 THEN x.a := x.a MOD y.a ELSE OSS.Mark("bad modulus") END
      ELSE
        IF (y.mode = Const) & (y.a <= 0) THEN  OSS.Mark("bad modulus") END ;
        loadAndMaybeSwap(x, y); Put0(MODx)
      END
    END
  END DivOp;

  PROCEDURE Relation*(op: INTEGER; VAR x, y: Item);   (* x := x ? y *)
  BEGIN
    IF (y.mode = Const) & (y.a = 0) & ((op = OSS.eql) OR (op = OSS.neq)) THEN
      IF op = OSS.eql THEN op := IFZERO ELSE op := IFNZRO END ;
    ELSE load(y);
      CASE op OF
        OSS.eql:
          Put0(EQ);
          op := IFNZRO
        | OSS.neq:
          Put0(EQ);
          op := IFZERO
        | OSS.lss:
          Put0(LT);
          op := IFNZRO
        | OSS.leq:
          Put0(SWAP);
          Put0(LT);
          op := IFZERO
        | OSS.gtr:
          Put0(SWAP);
          Put0(LT);
          op := IFNZRO
        | OSS.geq:
          Put0(LT);
          op := IFZERO
       END
    END ;
    SetCC(x, op)
  END Relation;

  PROCEDURE Store0*(VAR x: Item);
  BEGIN loadAdr(x)
  END Store0;

  PROCEDURE Store*(VAR x, y: Item); (* x := y *)
  BEGIN load(y);
    IF x.mode IN {Var, Indirect, Par} THEN Put0(STI); Put1(INCSP, -1)
    ELSE OSS.Mark("illegal assignment")
    END
  END Store;

  PROCEDURE VarParam*(VAR x: Item; ftype: Type);
  BEGIN
    IF x.mode IN {Var, Indirect, Par} THEN
      loadAdr(x)
    ELSE OSS.Mark("address error")
    END ;
    x.mode := Stack
  END VarParam;

  PROCEDURE ValueParam*(VAR x: Item);
  BEGIN load(x)
  END ValueParam;

  (*---------------------------------*)

  PROCEDURE CFJump*(VAR x: Item);  (*conditional forward jump*)
    VAR L0: INTEGER;
  BEGIN
    IF x.mode # Cond THEN loadCond(x) END ;
    L0 := pc;
    Put1(negated(x.r), x.a); FixLink(x.b); x.a := L0
  END CFJump;

  PROCEDURE FJump*(VAR L: INTEGER): INTEGER;  (*unconditional forward jump*)
    VAR L0: INTEGER;
  BEGIN L0 := pc;
    Put1(GOTO, L)
    RETURN L0
  END FJump;

  PROCEDURE CBJump*(VAR x: Item; L: INTEGER);  (*conditional backward jump*)
  BEGIN
    IF x.mode # Cond THEN loadCond(x) END ;
    Put1(negated(x.r), L); FixLink(x.b); FixLinkWith(x.a, L)
  END CBJump;

  PROCEDURE BJump*(L: INTEGER);  (*unconditional backward jump*)
  BEGIN Put1(GOTO, L)
  END BJump;

  PROCEDURE Call*(VAR obj: Object);
  BEGIN
    Put2(CALL, obj.type.nofpar, obj.val);
    IF obj.type.base.form = NoTyp THEN
      Put1(INCSP, -1)
    END
  END Call;

  PROCEDURE Enter*(parblksize, locblksize: INTEGER);
    VAR size: INTEGER;
  BEGIN size := locblksize - parblksize;
    IF size > 0 THEN
      Put1(INCSP, size)
    END
  END Enter;

  PROCEDURE Return*(form, size: INTEGER; VAR x: Item);
  BEGIN
    IF form = NoTyp THEN
      Put1(CSTI, 0)
    ELSE load(x)
    END ;
    Put1(RET, size)
  END Return;

  PROCEDURE Ord*(VAR x: Item);
  BEGIN load(x); x.type := intType
  END Ord;

  PROCEDURE Args*(VAR x: Item);
  BEGIN
    IF x.mode = Const THEN
      INC(x.a, globalDataSize);
      load(x)
    ELSE
      load(x);
      addOffset(globalDataSize)
    END ;
    x.type := intType;
    Put0(LDI)
  END Args;

  PROCEDURE Argnum*(VAR x: Item);
  BEGIN
    x.mode := Const;
    x.a := globalDataSize - 1;
    load(x);
    x.type := intType;
    Put0(LDI)
  END Argnum;

  PROCEDURE WriteInt*(VAR x: Item);
  BEGIN load(x); Put0(PRINTI); Put1(INCSP, -1)
  END WriteInt;

  PROCEDURE WriteChar*(VAR x: Item);
  BEGIN load(x); Put0(PRINTC); Put1(INCSP, -1)
  END WriteChar;

  PROCEDURE WriteLn*;
  BEGIN Put1(CSTI, 0AH); Put0(PRINTC); Put1(INCSP, -1)
  END WriteLn;

  PROCEDURE Init*;
  BEGIN pc := 0
  END Init;

  PROCEDURE Open*(size: INTEGER): INTEGER;
    VAR L0: INTEGER;
  BEGIN
    IF size > 0 THEN Put1(INCSP, size) END;
    globalDataSize := size;
    INC(globalDataSize); (* for ARGNUM value*)
    Put0(LDARGS);
    L0 := pc;
    Put1(GOTO, 0)
    RETURN L0
  END Open;

  PROCEDURE Header*(L: INTEGER);
  BEGIN
    (* Fix the GOTO destination in OSG.Open *)
    FixLink(L)
  END Header;

  PROCEDURE Close*;
  BEGIN Put0(STOP)
  END Close;


  (*-------------------- output -----------------------*)

  PROCEDURE GenObj*;
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE i < pc DO
      Out.Int(code[i], 2);
      INC(i)
    END ;
    Out.Ln
  END GenObj;

  PROCEDURE Decode*;
    VAR i, instr: INTEGER;
  BEGIN
    i := 0;
    WHILE i < pc DO
      instr := code[i];
      Out.Int(i, 3); Out.String("  ");
      IF (instr >= CSTI) & (instr <= STOP) THEN
        CASE instr OF
        CSTI:
          Out.String("CSTI "); Out.Int(code[i + 1], 3);
          INC(i)
        | ADD:   Out.String("ADD")
        | SUB:   Out.String("SUB")
        | MUL:   Out.String("MUL")
        | DIVx:  Out.String("DIV")
        | MODx:  Out.String("MOD")
        | EQ:    Out.String("EQ")
        | LT:    Out.String("LT")
        | NOT:   Out.String("NOT")
        | DUP:   Out.String("DUP")
        | SWAP:  Out.String("SWAP")
        | LDI:   Out.String("LDI")
        | STI:   Out.String("STI")
        | GETBP: Out.String("GETBP")
        | GETSP: Out.String("GETSP")
        | INCSP:
          Out.String("INCSP "); Out.Int(code[i + 1], 3);
          INC(i)
        | GOTO:
          Out.String("GOTO "); Out.Int(code[i + 1], 3);
          INC(i)
        | IFZERO:
          Out.String("IFZERO "); Out.Int(code[i + 1], 3);
          INC(i)
        | IFNZRO:
          Out.String("IFNZRO "); Out.Int(code[i + 1], 3);
          INC(i)
        | CALL:
          Out.String("CALL "); Out.Int(code[i + 1], 3);
          Out.String(" "); Out.Int(code[i + 2], 3);
          INC(i, 2)
        | TCALL:
          Out.String("TCALL "); Out.Int(code[i + 1], 3);
          Out.String(" "); Out.Int(code[i + 2], 3);
          Out.String(" "); Out.Int(code[i + 3], 3);
          INC(i, 3)
        | RET:
          Out.String("RET "); Out.Int(code[i + 1], 3);
          INC(i)
        | PRINTI: Out.String("PRINTI")
        | PRINTC: Out.String("PRINTC")
        | LDARGS: Out.String("LDARGS")
        | STOP:   Out.String("STOP")
        END
      ELSE
        Out.String("<unknown>")
      END ;
      Out.Ln;
      INC(i)
    END ;
    Out.Ln
  END Decode;

  PROCEDURE Execute*(VAR iargs: ARRAY OF INTEGER; argsLen: INTEGER);
    VAR bp, sp, pc, i, argc, pop: INTEGER;
      done: BOOLEAN;
      s: ARRAY 1000 OF INTEGER; (* The evaluation stack *)
  BEGIN
    bp := -999; (* Base pointer, for local variable access *)
    sp := -1; (* Stack top pointer *)
    pc := 0; (* Program counter: next instruction *)
    done := FALSE;
    WHILE ~done DO
      IF (code[pc] >= CSTI) & (code[pc] <= STOP) THEN
        CASE code[pc] OF
        CSTI: s[sp+1] := code[pc+1]; INC(pc, 2); INC(sp)
        | ADD: s[sp-1] := s[sp-1] + s[sp]; INC(pc); DEC(sp)
        | SUB: s[sp-1] := s[sp-1] - s[sp]; INC(pc); DEC(sp)
        | MUL: s[sp-1] := s[sp-1] * s[sp]; INC(pc); DEC(sp)
        | DIVx: s[sp-1] := s[sp-1] DIV s[sp]; INC(pc); DEC(sp)
        | MODx: s[sp-1] := s[sp-1] MOD s[sp]; INC(pc); DEC(sp)
        | EQ:
          IF s[sp-1] = s[sp] THEN s[sp-1] := 1 ELSE s[sp-1] := 0 END;
          INC(pc); DEC(sp)
        | LT:
          IF s[sp-1] < s[sp] THEN s[sp-1] := 1 ELSE s[sp-1] := 0 END;
          INC(pc); DEC(sp)
        | NOT:
          IF s[sp] = 0 THEN s[sp] := 1 ELSE s[sp] := 0 END;
          INC(pc)
        | DUP: s[sp+1] := s[sp]; INC(pc); INC(sp)
        | SWAP: i := s[sp]; s[sp] := s[sp-1]; s[sp-1] := i; INC(pc)
        | LDI: (* load indirect *) s[sp] := s[s[sp]]; INC(pc)
        | STI: (* store indirect, keep value on top *)
          s[s[sp-1]] := s[sp]; s[sp-1] := s[sp]; INC(pc); DEC(sp)
        | GETBP: s[sp+1] := bp; INC(pc); INC(sp)
        | GETSP: s[sp+1] := sp; INC(pc); INC(sp)
        | INCSP: sp := sp+code[pc+1]; INC(pc, 2)
        | GOTO: pc := code[pc+1]
        | IFZERO:
          IF s[sp] = 0 THEN pc := code[pc+1] ELSE INC(pc, 2) END;
          DEC(sp)
        | IFNZRO:
          IF s[sp] # 0 THEN pc := code[pc+1] ELSE INC(pc, 2) END;
          DEC(sp)
        | CALL:
          argc := code[pc+1]; INC(pc, 2);
          (* Make room for return address and old base pointer *)
          FOR i := 0 TO argc-1 DO
            s[sp-i+2] := s[sp-i]
          END ;
          s[sp-argc+1] := pc+1; INC(sp);
          s[sp-argc+1] := bp;   INC(sp);
          bp := sp+1-argc;
          pc := code[pc]
        | TCALL:
          argc := code[pc+1];  (* Number of new arguments *)
          pop := code[pc+2];  (* Number of variables to discard *)
          INC(pc, 3);
          i := argc-1;
          WHILE i >= 0 DO  (* Discard variables *)
            s[sp-i-pop] := s[sp-i];
            DEC(i)
          END ;
          sp := sp - pop; pc := code[pc]
        | RET:
          i := s[sp];
          sp := sp-code[pc+1]; bp := s[sp-1]; pc := s[sp-2]; DEC(sp, 2);
          s[sp] := i
        | PRINTI: Out.Int(s[sp], 3); INC(pc)
        | PRINTC: Out.Char(CHR(s[sp])); INC(pc)
        | LDARGS:
          INC(sp);
          s[sp] := argsLen;
          (* Push commandline arguments *)
          FOR i := 0 TO argsLen-1 DO
            INC(sp);
            s[sp] := iargs[i]
          END ;
          INC(pc)
        | STOP: done := TRUE
        END
      ELSE
        Out.String("Illegal instruction "); Out.Int(code[pc], 2);
        Out.String(" at address "); Out.Int(pc, 2)
      END
    END ;
    Out.Ln
  END Execute;

BEGIN
  NEW(boolType); boolType.form := Boolean; boolType.size := 1;
  NEW(intType); intType.form := Integer; intType.size := 1;
  NEW(noType); noType.form := NoTyp; noType.size := 1;
END OSG.
