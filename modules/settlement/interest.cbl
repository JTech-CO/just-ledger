       IDENTIFICATION DIVISION.
       PROGRAM-ID. INTEREST.
      *****************************************************************
      * Interest accrual batch — computes deposit / loan interest with
      * integer minor-unit amounts and rational (num/den) rates, never
      * touching floating point (INV-4). Two methods per input record:
      *
      *   'S' simple day-count:  interest = round_half_even(
      *          principal * rate_num * days, rate_den * basis)
      *   'C' compound per-period: balance accrues period interest
      *          round_half_even(balance * rate_num, rate_den), the
      *          interest being credited and rounded every period, for
      *          PERIODS periods; total = ending balance - principal.
      *
      * stdin (LINE SEQUENTIAL) -> stdout. Layout: copybook/interest-io.cpy
      * (single source of truth). Output must match the JS reference
      * (scripts/parity/lib.mjs) to the won. Rounding authority:
      * ROUNDED MODE IS NEAREST-EVEN. Overflow beyond the 15-digit output
      * fields is caught by ON SIZE ERROR and aborts (never truncated).
      *****************************************************************
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
      *    Bind stdin explicitly (KEYBOARD device mapping is disabled
      *    under -std=cobol2014). GnuCOBOL re-opens the path, so stdin
      *    must be a real file (shell redirect / fd), not a pipe.
      *    Output goes through DISPLAY (direct stdout stream, pipe-safe).
           SELECT INTEREST-IN  ASSIGN TO "/dev/stdin"
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-IN-STATUS.
       DATA DIVISION.
       FILE SECTION.
       FD  INTEREST-IN.
       01  IN-RAW               PIC X(63).
       WORKING-STORAGE SECTION.
       COPY "copybook/interest-io.cpy".
       01  WS-IN-STATUS         PIC XX.
       01  WS-EOF               PIC 9(01) VALUE 0.
       01  WS-P                 PIC 9(03) COMP.
      *    principal(15) * num(9) * days(5) reaches 29 digits, and in the
      *    compound path balance(18) * num(9) reaches 27 digits, so the
      *    product accumulator must hold up to 31 digits without loss.
       01  WS-PROD              PIC S9(31) PACKED-DECIMAL.
       01  WS-DENOM             PIC S9(18) PACKED-DECIMAL.
       01  WS-BAL               PIC S9(18) PACKED-DECIMAL.
       01  WS-PINT              PIC S9(18) PACKED-DECIMAL.
       PROCEDURE DIVISION.
       MAIN-PARA.
           OPEN INPUT INTEREST-IN.
           IF WS-IN-STATUS NOT = "00"
               DISPLAY "INTEREST: OPEN stdin failed, status "
                   WS-IN-STATUS UPON SYSERR
               STOP RUN WITH ERROR STATUS 8
           END-IF.
           PERFORM UNTIL WS-EOF = 1
               READ INTEREST-IN INTO INTEREST-IN-REC
                   AT END
                       MOVE 1 TO WS-EOF
                   NOT AT END
                       PERFORM ACCRUE-ONE
               END-READ
      *        any status other than ok/EOF must abort, never spin
               IF WS-IN-STATUS NOT = "00" AND WS-IN-STATUS NOT = "10"
                   DISPLAY "INTEREST: READ failed, status "
                       WS-IN-STATUS UPON SYSERR
                   STOP RUN WITH ERROR STATUS 8
               END-IF
           END-PERFORM.
           CLOSE INTEREST-IN.
           STOP RUN.
      *
       ACCRUE-ONE.
      *    contract: method is 'S' or 'C' only — never guess (a guessed
      *    method diverging from the JS reference is an INV-7 break).
           IF II-METHOD NOT = "S" AND II-METHOD NOT = "C"
               DISPLAY "INTEREST: invalid method " II-METHOD
                   UPON SYSERR
               STOP RUN WITH ERROR STATUS 8
           END-IF.
      *    a zero divisor is a malformed rate; stop before dividing.
           IF II-RATE-DEN = 0
               DISPLAY "INTEREST: rate_den is zero" UPON SYSERR
               STOP RUN WITH ERROR STATUS 8
           END-IF.
           MOVE II-ACCOUNT-ID TO IO-ACCOUNT-ID.
           MOVE II-METHOD     TO IO-METHOD.
           MOVE II-PRINCIPAL  TO IO-PRINCIPAL.
           IF II-METHOD = "S"
               PERFORM ACCRUE-SIMPLE
           ELSE
               PERFORM ACCRUE-COMPOUND
           END-IF.
           DISPLAY INTEREST-OUT-REC.
      *
       ACCRUE-SIMPLE.
      *    interest = round_half_even(principal * num * days, den * basis)
      *    one rounding over the whole span (day-count accrual).
           IF II-BASIS = 0
               DISPLAY "INTEREST: basis is zero (simple)" UPON SYSERR
               STOP RUN WITH ERROR STATUS 8
           END-IF.
           COMPUTE WS-PROD = II-PRINCIPAL * II-RATE-NUM * II-DAYS.
           COMPUTE WS-DENOM = II-RATE-DEN * II-BASIS.
           COMPUTE IO-INTEREST ROUNDED MODE IS NEAREST-EVEN =
               WS-PROD / WS-DENOM
               ON SIZE ERROR
                   DISPLAY "INTEREST: interest overflows 9(15)"
                       UPON SYSERR
                   STOP RUN WITH ERROR STATUS 8
           END-COMPUTE.
           COMPUTE IO-BALANCE = II-PRINCIPAL + IO-INTEREST
               ON SIZE ERROR
                   DISPLAY "INTEREST: balance overflows 9(15)"
                       UPON SYSERR
                   STOP RUN WITH ERROR STATUS 8
           END-COMPUTE.
      *
       ACCRUE-COMPOUND.
      *    balance accrues, crediting rounded interest each period; the
      *    per-period rate is num/den. Interest is rounded every period,
      *    which is what the JS reference does — the rounding cannot be
      *    deferred to the end or the two implementations would diverge.
           MOVE II-PRINCIPAL TO WS-BAL.
           PERFORM VARYING WS-P FROM 1 BY 1 UNTIL WS-P > II-PERIODS
               COMPUTE WS-PROD = WS-BAL * II-RATE-NUM
               COMPUTE WS-PINT ROUNDED MODE IS NEAREST-EVEN =
                   WS-PROD / II-RATE-DEN
                   ON SIZE ERROR
                       DISPLAY "INTEREST: period interest overflow"
                           UPON SYSERR
                       STOP RUN WITH ERROR STATUS 8
               END-COMPUTE
               ADD WS-PINT TO WS-BAL
                   ON SIZE ERROR
                       DISPLAY "INTEREST: compound balance overflow"
                           UPON SYSERR
                       STOP RUN WITH ERROR STATUS 8
               END-ADD
           END-PERFORM.
           COMPUTE IO-BALANCE = WS-BAL
               ON SIZE ERROR
                   DISPLAY "INTEREST: balance overflows 9(15)"
                       UPON SYSERR
                   STOP RUN WITH ERROR STATUS 8
           END-COMPUTE.
           COMPUTE IO-INTEREST = WS-BAL - II-PRINCIPAL
               ON SIZE ERROR
                   DISPLAY "INTEREST: interest overflows 9(15)"
                       UPON SYSERR
                   STOP RUN WITH ERROR STATUS 8
           END-COMPUTE.
