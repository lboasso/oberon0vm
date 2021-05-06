MODULE Permutations;  (*NW 22.1.2013 for Oberon-0*)
  VAR a: ARRAY 10 OF INTEGER;

  PROCEDURE perm(k, n: INTEGER; VAR a : ARRAY 10 OF INTEGER);
    VAR i, x: INTEGER;
  BEGIN
    IF k = 0 THEN i := 0;
      WHILE i < n DO WriteInt(a[i]); i := i+1 END ;
      WriteLn
    ELSE perm(k-1, n, a); i := 0;
      WHILE i < k-1 DO
        x := a[i]; a[i] := a[k-1]; a[k-1] := x;
        perm(k-1, n, a);
        x := a[i]; a[i] := a[k-1]; a[k-1] := x;
        i := i+1
      END
    END
  END perm;

BEGIN
  a[0] := ARGS(0); a[1] := ARGS(1); a[2] := ARGS(2);
  perm(3, 3, a)
END Permutations.
