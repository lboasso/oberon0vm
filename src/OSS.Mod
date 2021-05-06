(*
  Copyright 2021 Luca Boasso. All rights reserved.
  Use of this source code is governed by a MIT
  license that can be found in the LICENSE file.
*)

(* Scanner *)
MODULE OSS;
  IMPORT Strings, Files, Out;

  CONST IdLen* = 32;
    NKW = 25;  (*nof keywords*)
    maxKWX = 10; maxKWD = 10;
    maxSrcSize = 200000;
    maxErrMsgSize = 200;
    maxPath* = 200;

    (*lexical symbols*)
    null = 0; times* = 1; div* = 3; mod* = 4;
    and* = 5; plus* = 6; minus* = 7; or* = 8; eql* = 9;
    neq* = 10; lss* = 11; leq* = 12; gtr* = 13; geq* = 14;
    period* = 18;
    char* = 20; int* = 21; false* = 23; true* = 24;
    not* = 27; lparen* = 28; lbrak* = 29;
    ident* = 31;
    if* = 32; while* = 34; repeat* = 35;
    comma* = 40; colon* = 41; becomes* = 42;  rparen* = 44;
    rbrak* = 45; then* = 47; of* = 48; do* = 49;
    semicolon* = 52; end* = 53;
    else* = 55; elsif* = 56; until* = 57; return* = 58;
    array* = 60; record* = 61; const* = 63; type* = 64;
    var* = 65; procedure* = 66; begin* = 67;  module* = 69;
    eot = 71;

  TYPE Ident* = ARRAY IdLen OF CHAR;

  VAR val*: INTEGER;  (*results of Get*)
    id*: Ident;  (*for identifiers*)
    errcnt*: INTEGER;

    ch: CHAR;  (*last character read*)
    errpos: INTEGER;
    pos: INTEGER;
    EOF: BOOLEAN;
    k: INTEGER;
    KWX: ARRAY maxKWX OF INTEGER;
    keyTab: ARRAY NKW OF
        RECORD sym: INTEGER; id: ARRAY maxKWD OF CHAR END;
    src: ARRAY maxSrcSize OF BYTE;
    srcSize: INTEGER;
    line, prevLine, col, prevCol: INTEGER;
    inputPath: ARRAY maxPath OF CHAR;


  PROCEDURE Mark*(msg: ARRAY OF CHAR);
    VAR out: ARRAY maxErrMsgSize OF CHAR;
  BEGIN
    IF (pos > errpos) & (errcnt < 25) THEN
      Strings.Append(inputPath, out);
      Strings.AppendChar(":", out);
      Strings.AppendInt(prevLine, 0, out);
      Strings.AppendChar(":", out);
      Strings.AppendInt(prevCol, 0, out);
      Strings.Append(": ", out);
      Strings.Append(msg, out);
      Out.String(out);
      Out.Ln;
      INC(errcnt); errpos := pos + 4
    END
  END Mark;

  PROCEDURE read();
  BEGIN
    IF pos < srcSize THEN
      ch := CHR(src[pos]);
      IF ch = 0AX THEN (* 0AX = \n *)
        col := 0;
        INC(line)
      ELSE
        INC(col);
      END ;
      INC(pos)
    ELSE
      EOF := TRUE;
      ch := 0X
    END
  END read;


  PROCEDURE Identifier(VAR sym: INTEGER);
    VAR i, k: INTEGER;
  BEGIN i := 0;
    REPEAT
      IF i < IdLen-1 THEN id[i] := ch; INC(i) END ;
      read
    UNTIL (ch < "0") OR (ch > "9") & (ch < "A") OR (ch > "Z") & (ch < "a") OR
          (ch > "z");
    id[i] := 0X;
    IF i < maxKWX THEN k := KWX[i-1];  (*search for keyword*)
      WHILE (k < KWX[i]) & (id # keyTab[k].id) DO INC(k) END ;
      IF k < KWX[i] THEN sym := keyTab[k].sym ELSE sym := ident END
    ELSE sym := ident
    END
  END Identifier;

  PROCEDURE Number(VAR sym: INTEGER);
    CONST max = 2147483647 (*2^31 - 1*);
    VAR d: INTEGER;
  BEGIN
    val := 0;
    sym := int;
    REPEAT
        d := ORD(ch) - ORD("0");
        IF d < 10 THEN
          IF val <= (max-d) DIV 10 THEN
            val := val*10 + d
          ELSE
            Mark("too large"); val := 0
          END
        ELSE Mark("bad integer")
        END ;
        read
    UNTIL (ch < "0") OR (ch > "9")
  END Number;

  PROCEDURE comment;
    VAR level: INTEGER;
  BEGIN
    level := 1; read;
    WHILE ~EOF & (level > 0) DO
      IF ch = "(" THEN read;
        IF ch = "*" THEN INC(level); read END
      ELSIF ch = "*" THEN read;
        IF ch = ")" THEN DEC(level); read END
      ELSE read
      END
    END ;
    IF level # 0 THEN Mark("unterminated comment") END
  END comment;

  PROCEDURE Get*(VAR sym: INTEGER);
  BEGIN
    prevLine := line;
    prevCol := col;
    REPEAT
      WHILE ~EOF & (ch <= " ") DO read END;
      IF EOF THEN sym := eot
      ELSIF ch <= 7FX THEN
        CASE ch OF (* " " < ch <= 7FX *)
          "!", "%", "'", "?", "@", "\", "_", "`": read; sym := null
          | 22X : (* " *) read; val := ORD(ch); sym := char; read;
                  IF ch # 22X THEN
                    Mark("Illegal character terminator")
                  END ;
                  read
          | "#" : read; sym := neq
          | "&" : read; sym := and
          | "(" : read;
                  IF ch = "*" THEN sym := null; comment
                  ELSE sym := lparen END
          | ")" : read; sym := rparen
          | "*" : read; sym := times
          | "+" : read; sym := plus
          | "," : read; sym := comma
          | "-" : read; sym := minus
          | "." : read;
                  sym := period
          | "0".."9": Number(sym)
          | ":" : read;
                  IF ch = "=" THEN read; sym := becomes
                  ELSE sym := colon END
          | ";" : read; sym := semicolon
          | "<" : read;
                  IF ch = "=" THEN read; sym := leq
                  ELSE sym := lss END
          | "=" : read; sym := eql
          | ">" : read;
                  IF ch = "=" THEN read; sym := geq
                  ELSE sym := gtr END
          | "A".."Z": Identifier(sym)
          | "[" : read; sym := lbrak
          | "]" : read; sym := rbrak
          | "a".."z": Identifier(sym)
          | "~" : read; sym := not
        END
      ELSE read; sym := null
      END
    UNTIL sym # null
  END Get;

  PROCEDURE Init*(path: ARRAY OF CHAR);
    VAR f: Files.File;
      n, len: INTEGER;
  BEGIN
    pos := 0; line := 1; col := 0;
    EOF := FALSE; errpos := -1; errcnt := 0;
    Strings.Copy(path, inputPath);
    f := Files.Open(path);
    IF f = NIL THEN
      Mark("file not found")
    ELSE
      len := Files.Size(f);
      IF (len = -1) OR (len >= maxSrcSize) THEN
        Mark("file too big")
      ELSE
        Files.ReadBytes(f, src, n);
        srcSize := n;
        IF Files.Status(f) # Files.OK THEN
          Mark("error while reading the file")
        END ;
        read
      END ;
      Files.Close(f)
    END
  END Init;

  PROCEDURE EnterKW(sym: INTEGER; name: ARRAY OF CHAR);
  BEGIN keyTab[k].id := name; keyTab[k].sym := sym; INC(k)
  END EnterKW;

BEGIN k := 0; KWX[0] := 0; KWX[1] := 0;
  EnterKW(if, "IF");
  EnterKW(do, "DO");
  EnterKW(of, "OF");
  EnterKW(or, "OR");
  KWX[2] := k;
  EnterKW(end, "END");
  EnterKW(var, "VAR");
  EnterKW(div, "DIV");
  EnterKW(mod, "MOD");
  KWX[3] := k;
  EnterKW(else, "ELSE");
  EnterKW(then, "THEN");
  EnterKW(true, "TRUE");
  EnterKW(type, "TYPE");
  KWX[4] := k;
  EnterKW(elsif, "ELSIF");
  EnterKW(false, "FALSE");
  EnterKW(array, "ARRAY");
  EnterKW(begin, "BEGIN");
  EnterKW(const, "CONST");
  EnterKW(until, "UNTIL");
  EnterKW(while, "WHILE");
  KWX[5] := k;
  EnterKW(record, "RECORD");
  EnterKW(repeat, "REPEAT");
  EnterKW(return, "RETURN");
  EnterKW(module, "MODULE");
  KWX[6] := k;
  KWX[7] := k; KWX[8] := k;
  EnterKW(procedure, "PROCEDURE");
  KWX[9] := k;
END OSS.
