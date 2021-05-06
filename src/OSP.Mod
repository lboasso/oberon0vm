(*
  Copyright 2021 Luca Boasso. All rights reserved.
  Use of this source code is governed by a MIT
  license that can be found in the LICENSE file.
*)

(* Parser *)
MODULE OSP;
  IMPORT OSS, OSG, Out;

  VAR sym, level: INTEGER;
    topScope, dummy: OSG.Object;
    expression1: PROCEDURE (VAR x: OSG.Item);  (*to avoid forward reference*)

  PROCEDURE NewObj(VAR obj: OSG.Object; class: INTEGER);
    VAR new, x: OSG.Object;
  BEGIN x := topScope;
    WHILE (x.next # NIL) & (x.next.name # OSS.id) DO x := x.next END ;
    IF x.next = NIL THEN
      NEW(new); new.name := OSS.id; new.class := class; new.next := NIL;
      x.next := new; obj := new
    ELSE obj := x.next; OSS.Mark("mult def")
    END
  END NewObj;

  PROCEDURE find(VAR obj: OSG.Object);
    VAR s, x: OSG.Object;
  BEGIN s := topScope;
    REPEAT x := s.next;
      WHILE (x # NIL) & (x.name # OSS.id) DO x := x.next END ;
      s := s.dsc
    UNTIL (x # NIL) OR (s = NIL);
    IF x = NIL THEN x := dummy; OSS.Mark("undef") END ;
    obj := x
  END find;

  PROCEDURE FindField(VAR obj: OSG.Object; list: OSG.Object);
  BEGIN
    WHILE (list # NIL) & (list.name # OSS.id) DO list := list.next END ;
    IF list # NIL THEN obj := list ELSE OSS.Mark("undef"); obj := dummy END
  END FindField;

  PROCEDURE Check(s: INTEGER; msg: ARRAY OF CHAR);
  BEGIN
    IF sym = s THEN OSS.Get(sym) ELSE OSS.Mark(msg) END
  END Check;

  PROCEDURE CheckInt(VAR x: OSG.Item);
  BEGIN
    IF x.type.form # OSG.Integer THEN OSS.Mark("not integer") END
  END CheckInt;

  PROCEDURE CheckBool(VAR x: OSG.Item);
  BEGIN
    IF x.type.form # OSG.Boolean THEN OSS.Mark("not Boolean") END
  END CheckBool;

  PROCEDURE OpenScope;
    VAR s: OSG.Object;
  BEGIN NEW(s); s.class := OSG.Head; s.dsc := topScope; s.next := NIL; topScope := s
  END OpenScope;

  PROCEDURE CloseScope;
  BEGIN topScope := topScope.dsc
  END CloseScope;

  (* -------------------- Parser ---------------------*)

  PROCEDURE selector(VAR x: OSG.Item);
    VAR y: OSG.Item; obj: OSG.Object;
  BEGIN
    WHILE (sym = OSS.lbrak) OR (sym = OSS.period) DO
      IF sym = OSS.lbrak THEN
        OSS.Get(sym); expression1(y);
        IF x.type.form = OSG.Array THEN
          CheckInt(y); OSG.Index(x, y); x.type := x.type.base
        ELSE OSS.Mark("not an array")
        END ;
        Check(OSS.rbrak, "no ]")
      ELSE (*period*) OSS.Get(sym);
        IF sym = OSS.ident THEN
          IF x.type.form = OSG.Record THEN
            FindField(obj, x.type.dsc); OSS.Get(sym);
            IF obj # dummy THEN OSG.Field(x, obj); x.type := obj.type END
          ELSE OSS.Mark("not a record")
          END
        ELSE OSS.Mark("ident?")
        END
      END
    END
  END selector;

  PROCEDURE CompTypes(t0, t1: OSG.Type): BOOLEAN;
  BEGIN (*Compatible Types*)
    RETURN (t0 = t1)
      OR (t0.form = OSG.Array) & (t1.form = OSG.Array) & (t0.len = t1.len) &
      CompTypes(t0.base, t1.base)
  END CompTypes;

  PROCEDURE Parameter(par: OSG.Object);
    VAR x: OSG.Item; varpar: BOOLEAN;
  BEGIN expression1(x);
    IF par # NIL THEN
      varpar := par.class = OSG.Par;
      IF CompTypes(par.type, x.type) THEN
        IF ~varpar THEN OSG.ValueParam(x)
        ELSE OSG.VarParam(x, par.type)
        END
      ELSE OSS.Mark("incompatible parameters")
      END
    END
  END Parameter;

  PROCEDURE ParamList(VAR obj: OSG.Object);
    VAR n: INTEGER; par: OSG.Object;
  BEGIN par := obj.dsc; n := 0;
    IF sym # OSS.rparen THEN
      Parameter(par); n := 1;
      WHILE sym <= OSS.comma DO
        Check(sym, "comma?");
        IF par # NIL THEN par := par.next END ;
        INC(n); Parameter(par)
      END ;
      Check(OSS.rparen, ") missing")
    ELSE OSS.Get(sym);
    END ;
    IF n < obj.type.nofpar THEN OSS.Mark("too few params")
    ELSIF n > obj.type.nofpar THEN OSS.Mark("too many params")
    END
  END ParamList;

  PROCEDURE StandFunc(VAR x: OSG.Item; fctno: INTEGER);
  BEGIN
    IF sym = OSS.lparen THEN
      OSS.Get(sym);
      IF fctno = 0 THEN (*ORD*) expression1(x); OSG.Ord(x)
      ELSIF fctno = 1 THEN (*ARGS*) expression1(x);
        IF x.a < 0 THEN OSS.Mark("bad index") END;
        OSG.Args(x)
      ELSIF fctno = 2 THEN (*ARGNUM*)
        OSG.Argnum(x)
      END ;
      IF sym = OSS.rparen THEN OSS.Get(sym) ELSE OSS.Mark(") expected") END
    ELSE OSS.Mark("param missing"); OSG.MakeConstItem(x, OSG.intType, 0)
    END
  END StandFunc;

  PROCEDURE factor(VAR x: OSG.Item);
    VAR obj: OSG.Object;
  BEGIN (*sync*)
    IF (sym < OSS.char) OR (sym > OSS.ident) THEN OSS.Mark("expression expected");
      REPEAT OSS.Get(sym) UNTIL (sym >= OSS.int) & (sym <= OSS.ident)
    END ;
    IF sym = OSS.ident THEN
      find(obj); OSS.Get(sym);
      IF obj.class = OSG.SFunc THEN
        IF obj.type = NIL THEN OSS.Mark("not a function"); obj.type := OSG.intType END ;
        StandFunc(x, obj.val); x.type := obj.type
      ELSE OSG.MakeItem(x, obj, level); selector(x);
        IF sym = OSS.lparen THEN
          OSS.Get(sym);
          IF (x.type.form = OSG.Proc) & (x.type.base.form # OSG.NoTyp) THEN
            ParamList(obj); OSG.Call(obj);
            x.type := x.type.base
          ELSE OSS.Mark("not a function"); ParamList(obj)
          END
        END
      END
    ELSIF sym = OSS.int THEN OSG.MakeConstItem(x, OSG.intType, OSS.val); OSS.Get(sym)
    ELSIF sym = OSS.char THEN OSG.MakeConstItem(x, OSG.intType, OSS.val); OSS.Get(sym)
    ELSIF sym = OSS.lparen THEN
      OSS.Get(sym);
      IF sym # OSS.rparen THEN expression1(x) END ;
      Check(OSS.rparen, "no )")
    ELSIF sym = OSS.not THEN OSS.Get(sym); factor(x); CheckBool(x); OSG.Not(x)
    ELSIF sym = OSS.false THEN OSS.Get(sym); OSG.MakeConstItem(x, OSG.boolType, 0)
    ELSIF sym = OSS.true THEN OSS.Get(sym); OSG.MakeConstItem(x, OSG.boolType, 1)
    ELSE OSS.Mark("factor?"); OSG.MakeItem(x, dummy, level)
    END
  END factor;

  PROCEDURE term(VAR x: OSG.Item);
    VAR y: OSG.Item; op: INTEGER;
  BEGIN factor(x);
    WHILE (sym >= OSS.times) & (sym <= OSS.and) DO
      op := sym; OSS.Get(sym);
      IF op = OSS.times THEN
        OSG.loadOp(x); CheckInt(x); factor(y); CheckInt(y); OSG.MulOp(x, y)
      ELSIF (op = OSS.div) OR (op = OSS.mod) THEN
        OSG.loadOp(x); CheckInt(x); factor(y); CheckInt(y); OSG.DivOp(op, x, y)
      ELSE (*op = and*) CheckBool(x); OSG.And1(x); factor(y); CheckBool(y); OSG.And2(x, y)
      END
    END
  END term;

  PROCEDURE SimpleExpression(VAR x: OSG.Item);
    VAR y: OSG.Item; op: INTEGER;
  BEGIN
    IF sym = OSS.plus THEN OSS.Get(sym); term(x); CheckInt(x)
    ELSIF sym = OSS.minus THEN OSS.Get(sym); term(x); CheckInt(x); OSG.Neg(x)
    ELSE term(x)
    END;
    WHILE (sym >= OSS.plus) & (sym <= OSS.or) DO
      op := sym; OSS.Get(sym);
      IF op = OSS.or THEN OSG.Or1(x); CheckBool(x); term(y); CheckBool(y); OSG.Or2(x, y)
      ELSE OSG.loadOp(x); CheckInt(x); term(y); CheckInt(y); OSG.AddOp(op, x, y)
      END
    END
  END SimpleExpression;

  PROCEDURE expression(VAR x: OSG.Item);
    VAR y: OSG.Item; op: INTEGER;
  BEGIN SimpleExpression(x);
    IF (sym >= OSS.eql) & (sym <= OSS.geq) THEN
      op := sym; OSS.Get(sym); OSG.loadOp0(x); SimpleExpression(y);
      IF x.type = y.type THEN OSG.Relation(op, x, y) ELSE OSS.Mark("incompatible types") END ;
      x.type := OSG.boolType
    END
  END expression;

  PROCEDURE StandProc(pno: INTEGER);
    VAR x: OSG.Item;
  BEGIN
    IF (sym = OSS.lparen) & (pno < 2) THEN
      OSS.Get(sym); expression(x);
      IF pno = 0 THEN  CheckInt(x); OSG.WriteInt(x)
      ELSIF pno = 1 THEN OSG.WriteChar(x) END ;
      IF sym = OSS.rparen THEN OSS.Get(sym) ELSE OSS.Mark("no )") END
    ELSIF pno = 2 THEN OSG.WriteLn
    END
  END StandProc;

  PROCEDURE StatSequence;
    VAR obj: OSG.Object; x, y: OSG.Item; L: INTEGER;
  BEGIN (* StatSequence *)
    REPEAT (*sync*)
      IF ~((sym = OSS.ident) OR (sym >= OSS.if) & (sym <= OSS.repeat) OR (sym >= OSS.semicolon)) THEN
        OSS.Mark("statement expected");
        REPEAT OSS.Get(sym) UNTIL (sym = OSS.ident) OR (sym >= OSS.if)
      END ;
      IF sym = OSS.ident THEN
        find(obj); OSS.Get(sym);
        IF obj.class = OSG.SProc THEN StandProc(obj.val)
        ELSE OSG.MakeItem(x, obj, level); selector(x);
          IF sym = OSS.becomes THEN (*assignment*)
            OSG.Store0(x);
            OSS.Get(sym); expression(y);
            IF (x.type.form IN {OSG.Boolean, OSG.Integer}) & (x.type.form = y.type.form) THEN OSG.Store(x, y)
            ELSE OSS.Mark("incompatible assignment")
            END
          ELSIF sym = OSS.eql THEN OSS.Mark("should be :="); OSS.Get(sym); expression(y)
          ELSIF sym = OSS.lparen THEN (*procedure call*)
            OSS.Get(sym);
            IF (obj.class = OSG.Proc) & (obj.type.base.form = OSG.NoTyp) THEN ParamList(obj); OSG.Call(obj);
            ELSE OSS.Mark("not a procedure")
            END
          ELSIF obj.class = OSG.Proc THEN (*procedure call without parameters*)
            IF obj.type.nofpar > 0 THEN OSS.Mark("missing parameters") END ;
            IF obj.type.base.form = OSG.NoTyp THEN OSG.Call(obj) ELSE OSS.Mark("not a procedure") END
          ELSIF obj.class = OSG.Typ THEN OSS.Mark("illegal assignment")
          ELSE OSS.Mark("not a procedure")
          END
        END
      ELSIF sym = OSS.if THEN
        OSS.Get(sym); expression(x); CheckBool(x); OSG.CFJump(x); Check(OSS.then, "no THEN");
        StatSequence; L := 0;
        WHILE sym = OSS.elsif DO
          OSS.Get(sym); L := OSG.FJump(L); OSG.FixLink(x.a); expression(x); CheckBool(x); OSG.CFJump(x);
          IF sym = OSS.then THEN OSS.Get(sym) ELSE OSS.Mark("THEN?") END ;
          StatSequence
        END ;
        IF sym = OSS.else THEN
          OSS.Get(sym); L := OSG.FJump(L); OSG.FixLink(x.a); StatSequence
        ELSE OSG.FixLink(x.a)
        END ;
        OSG.FixLink(L);
        IF sym = OSS.end THEN OSS.Get(sym) ELSE OSS.Mark("END?") END
      ELSIF sym = OSS.while THEN
        OSS.Get(sym); L := OSG.pc; expression(x); CheckBool(x); OSG.CFJump(x);
        Check(OSS.do, "no DO"); StatSequence; OSG.BJump(L); OSG.FixLink(x.a);
        Check(OSS.end, "no END")
      ELSIF sym = OSS.repeat THEN
        OSS.Get(sym); L := OSG.pc; StatSequence;
        IF sym = OSS.until THEN
          OSS.Get(sym); expression(x); CheckBool(x); OSG.CBJump(x, L)
        ELSE OSS.Mark("missing UNTIL")
        END
      END ;
      IF sym = OSS.semicolon THEN OSS.Get(sym)
      ELSIF sym < OSS.semicolon THEN OSS.Mark("missing semicolon?")
      END
    UNTIL sym > OSS.semicolon
  END StatSequence;

  PROCEDURE IdentList(class: INTEGER; VAR first: OSG.Object);
    VAR obj: OSG.Object;
  BEGIN
    IF sym = OSS.ident THEN
      NewObj(first, class); OSS.Get(sym);
      WHILE sym = OSS.comma DO
        OSS.Get(sym);
        IF sym = OSS.ident THEN NewObj(obj, class); OSS.Get(sym)
        ELSE OSS.Mark("ident?")
        END
      END;
      Check(OSS.colon, "no :")
    END
  END IdentList;

  PROCEDURE Type(VAR type: OSG.Type);
    VAR obj, first: OSG.Object; x: OSG.Item; tp: OSG.Type;
  BEGIN type := OSG.intType; (*sync*)
    IF (sym # OSS.ident) & (sym < OSS.array) THEN OSS.Mark("type?");
      REPEAT OSS.Get(sym) UNTIL (sym = OSS.ident) OR (sym >= OSS.array)
    END ;
    IF sym = OSS.ident THEN
      find(obj); OSS.Get(sym);
      IF obj.class = OSG.Typ THEN type := obj.type ELSE OSS.Mark("type?") END
    ELSIF sym = OSS.array THEN
      OSS.Get(sym); expression(x);
      IF (x.mode # OSG.Const) OR (x.a < 0) THEN OSS.Mark("bad index") END ;
      IF sym = OSS.of THEN OSS.Get(sym) ELSE OSS.Mark("OF?") END ;
      Type(tp); NEW(type); type.form := OSG.Array; type.base := tp;
      type.len := x.a; type.size := type.len * tp.size
    ELSIF sym = OSS.record THEN
      OSS.Get(sym); NEW(type); type.form := OSG.Record; type.size := 0; OpenScope;
      REPEAT
        IF sym = OSS.ident THEN
          IdentList(OSG.Fld, first); Type(tp); obj := first;
          WHILE obj # NIL DO
            obj.type := tp; obj.val := type.size; type.size := type.size + obj.type.size; obj := obj.next
          END
        END ;
        IF sym = OSS.semicolon THEN OSS.Get(sym)
        ELSIF sym = OSS.ident THEN OSS.Mark("; ?")
        END
      UNTIL sym # OSS.ident;
      type.dsc := topScope.next; CloseScope; Check(OSS.end, "no END")
    ELSE OSS.Mark("ident?")
    END
  END Type;


  PROCEDURE Declarations(VAR varsize: INTEGER);
    VAR obj, first: OSG.Object;
      x: OSG.Item; tp: OSG.Type;
  BEGIN (*sync*)
    IF (sym < OSS.const) & (sym # OSS.end) THEN OSS.Mark("declaration?");
      REPEAT OSS.Get(sym) UNTIL (sym >= OSS.const) OR (sym = OSS.end)
    END ;
    IF sym = OSS.const THEN
      OSS.Get(sym);
      WHILE sym = OSS.ident DO
        NewObj(obj, OSG.Const); OSS.Get(sym);
        IF sym = OSS.eql THEN OSS.Get(sym) ELSE OSS.Mark("=?") END;
        expression(x);
        IF x.mode = OSG.Const THEN obj.val := x.a; obj.type := x.type
        ELSE OSS.Mark("expression not constant")
        END ;
        Check(OSS.semicolon, "; expected")
      END
    END ;
    IF sym = OSS.type THEN
      OSS.Get(sym);
      WHILE sym = OSS.ident DO
        NewObj(obj, OSG.Typ); OSS.Get(sym);
        IF sym = OSS.eql THEN OSS.Get(sym) ELSE OSS.Mark("=?") END ;
        Type(obj.type); Check(OSS.semicolon, "; expected")
      END
    END ;
    IF sym = OSS.var THEN
      OSS.Get(sym);
      WHILE sym = OSS.ident DO
        IdentList(OSG.Var, first); Type(tp);
        obj := first;
        WHILE obj # NIL DO
          obj.type := tp; obj.lev := level;
          obj.val := varsize; varsize := varsize + obj.type.size; obj := obj.next
        END ;
        Check(OSS.semicolon, "; expected")
      END
    END ;
    IF (sym >= OSS.const) & (sym <= OSS.var) THEN OSS.Mark("declaration in bad order") END
  END Declarations;

  PROCEDURE ProcedureDecl;
    VAR proc, obj: OSG.Object;
      ptype: OSG.Type;
      procid: OSS.Ident;
      nofpar: INTEGER;
      locblksize, parblksize: INTEGER;
      x: OSG.Item;

    PROCEDURE FPSection(VAR adr: INTEGER; VAR nofpar: INTEGER);
      VAR obj, first: OSG.Object; tp: OSG.Type; parsize: INTEGER;
    BEGIN
      IF sym = OSS.var THEN OSS.Get(sym); IdentList(OSG.Par, first)
      ELSE IdentList(OSG.Var, first)
      END ;
      IF sym = OSS.ident THEN
        find(obj); OSS.Get(sym);
        IF obj.class = OSG.Typ THEN tp := obj.type ELSE OSS.Mark("type?"); tp := OSG.intType END
      ELSIF sym = OSS.array THEN Type(tp)
      ELSE OSS.Mark("ident?"); tp := OSG.intType
      END ;
      IF first.class = OSG.Var THEN
        parsize := tp.size;
        IF tp.form >= OSG.Array THEN OSS.Mark("no struct params") END ;
      ELSE parsize := 1
      END ;
      obj := first;
      WHILE obj # NIL DO
        INC(nofpar); obj.type := tp; obj.lev := level; obj.val := adr; adr := adr + parsize;
        obj := obj.next
      END
    END FPSection;

  BEGIN (* ProcedureDecl *) OSS.Get(sym);
    IF sym = OSS.ident THEN
      procid := OSS.id;
      NewObj(proc, OSG.Proc); OSS.Get(sym); parblksize := 0; nofpar := 0;
      OpenScope;  INC(level); proc.val := -1;
      IF sym = OSS.lparen THEN
        OSS.Get(sym);
        IF sym = OSS.rparen THEN OSS.Get(sym)
        ELSE FPSection(parblksize, nofpar);
          WHILE sym = OSS.semicolon DO OSS.Get(sym); FPSection(parblksize, nofpar) END ;
          IF sym = OSS.rparen THEN OSS.Get(sym) ELSE OSS.Mark(")?") END
        END
      END ;
      locblksize := parblksize; NEW(proc.type);
      ptype := proc.type;
      ptype.form := OSG.Proc;
      ptype.nofpar := nofpar;
      ptype.base := OSG.noType;
      IF sym = OSS.colon THEN  (*function*)
        OSS.Get(sym);
        IF sym = OSS.ident THEN find(obj); OSS.Get(sym); ptype.base := obj.type;
          IF ~((obj.class = OSG.Typ) & ((obj.type.form = OSG.Boolean) OR (obj.type.form = OSG.Integer))) THEN
          OSS.Mark("illegal function type")
          END
        ELSE OSS.Mark("type identifier expected")
        END
      END ;
      Check(OSS.semicolon, "; expected");
      Declarations(locblksize); proc.dsc := topScope.next;
      WHILE sym = OSS.procedure DO
        ProcedureDecl; Check(OSS.semicolon, "; expected")
      END ;
      proc.val := OSG.pc; OSG.Enter(parblksize, locblksize);
      IF sym = OSS.begin THEN OSS.Get(sym); StatSequence END ;
      IF sym = OSS.return THEN
        OSS.Get(sym); expression(x);
        IF ptype.base = OSG.noType THEN OSS.Mark("this is not a function")
        ELSIF ~CompTypes(ptype.base, x.type) THEN
          OSS.Mark("wrong result type")
        END
      ELSIF ptype.base.form # OSG.NoTyp THEN
        OSS.Mark("function without result"); ptype.base := OSG.noType
      END ;
      Check(OSS.end, "no END");
      IF sym = OSS.ident THEN
        IF procid # OSS.id THEN OSS.Mark("no match") END ;
        OSS.Get(sym)
      ELSE OSS.Mark("no proc id")
      END ;
      OSG.Return(ptype.base.form, locblksize, x); DEC(level); CloseScope
    END
  END ProcedureDecl;

  PROCEDURE Module;
    VAR modid: OSS.Ident; dc, L: INTEGER;
  BEGIN
    IF sym = OSS.module THEN
      OSS.Get(sym);
      OSG.Init; OpenScope; dc := 0; level := 0;
      IF sym = OSS.ident THEN
        modid := OSS.id; OSS.Get(sym);
      ELSE OSS.Mark("ident?")
      END ;
      Check(OSS.semicolon, "; expected");
      Declarations(dc);
      L := OSG.Open(dc);
      WHILE sym = OSS.procedure DO ProcedureDecl; Check(OSS.semicolon, "; expected") END ;
      OSG.Header(L);
      IF sym = OSS.begin THEN OSS.Get(sym); StatSequence END ;
      Check(OSS.end, "no END");
      IF sym = OSS.ident THEN
        IF modid # OSS.id THEN OSS.Mark("no match") END ;
        OSS.Get(sym)
      ELSE OSS.Mark("ident?")
      END ;
      IF sym # OSS.period THEN OSS.Mark(". ?") END ;
      CloseScope;
      OSG.Close
    ELSE OSS.Mark("MODULE?")
    END
  END Module;

  PROCEDURE toNum(buf: ARRAY OF CHAR): INTEGER;
    CONST max = 2147483647 (*2^31 - 1*);
    VAR val, d, i: INTEGER; err: BOOLEAN;
  BEGIN
    i := 0;
    val := 0;
    err := FALSE;
    WHILE (buf[i] # 0X) & ~err DO
        d := ORD(buf[i]) - ORD("0");
        IF d < 10 THEN
          IF val <= (max-d) DIV 10 THEN
            val := val*10 + d
          ELSE
            val := 0; err := TRUE
          END
        ELSE val := 0; err := TRUE
        END ;
        INC(i)
    END
    RETURN val
  END toNum;

  PROCEDURE Main();
    CONST MaxBuf = 10; MaxArgs = 20;
    VAR path: ARRAY 100 OF CHAR; iargs: ARRAY MaxArgs OF INTEGER;
      n, i, j: INTEGER; buf: ARRAY MaxBuf OF CHAR;
  BEGIN
    n := ARGNUM();
    IF n < 1 THEN
      Out.String("Usage: OJP sourceFile.Mod [intArg0, intArg1, ..]"); Out.Ln;
    ELSE
      ARGS(0, path);
      OSS.Init(path); OSS.Get(sym); Module;
      IF OSS.errcnt = 0 THEN
        Out.String("---ASSEMBLY---"); Out.Ln;
        OSG.Decode;
        Out.String("---RUN---"); Out.Ln;
        i := 1;
        j := 0;
        WHILE (i < n) & (j < MaxArgs) DO
          ARGS(i, buf);
          iargs[j] := toNum(buf);
          INC(i);
          INC(j);
        END ;
        OSG.Execute(iargs, j)
      END
    END
  END Main;

  PROCEDURE enter(name: ARRAY OF CHAR; cl: INTEGER; n: INTEGER;  type: OSG.Type);
    VAR obj: OSG.Object;
  BEGIN NEW(obj);
    obj.class := cl; obj.val := n; obj.name := name; obj.type := type; obj.dsc := NIL;
    obj.next := topScope.next; topScope.next := obj
  END enter;

BEGIN
  NEW(dummy); dummy.class := OSG.Var; dummy.type := OSG.intType; dummy.val := 0;
  topScope := NIL; OpenScope; expression1 := expression;
  enter("WriteInt", OSG.SProc, 0,  OSG.noType);
  enter("WriteChar", OSG.SProc, 1, OSG.noType);
  enter("WriteLn", OSG.SProc, 2, OSG.noType);
  enter("ORD", OSG.SFunc, 0, OSG.intType);
  enter("ARGS", OSG.SFunc, 1, OSG.intType);
  enter("ARGNUM", OSG.SFunc, 2, OSG.intType);
  enter("BOOLEAN", OSG.Typ, 0, OSG.boolType);
  enter("INTEGER", OSG.Typ, 1, OSG.intType)
END OSP.
