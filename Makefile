.POSIX:
.SUFFIXES:

OBERON0_SOURCES = src/OSS.Mod src/OSG.Mod src/OSP.Mod

build:
	mkdir -p out/
	java -cp $(OBERON_BIN) oberonc out $(OBERON0_SOURCES)

factorial: build
	java -cp $(OBERON_BIN):out OSP examples/Factorial.Mod

fractions: build
	java -cp $(OBERON_BIN):out OSP examples/Fractions.Mod 20

magicSquares: build
	java -cp $(OBERON_BIN):out OSP examples/MagicSquares.Mod 3

permutations: build
	java -cp $(OBERON_BIN):out OSP examples/Permutations.Mod 3 7 11

powers: build
	java -cp $(OBERON_BIN):out OSP examples/Powers.Mod 32

primeNumbers: build
	java -cp $(OBERON_BIN):out OSP examples/PrimeNumbers.Mod 20

clean:
	rm -rf out/
