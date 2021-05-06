MODULE Factorial;

  PROCEDURE fact(n: INTEGER) : INTEGER;
    VAR res: INTEGER;
  BEGIN
    IF n = 0 THEN res := 1;
    ELSE res := fact(n-1)*n
    END
    RETURN res
  END fact;

BEGIN
  WriteInt(fact(8))
END Factorial.
