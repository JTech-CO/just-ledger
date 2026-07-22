       IDENTIFICATION DIVISION.
       PROGRAM-ID. AMORT.
      *****************************************************************
      * Level-payment amortization schedule — split each period into
      * interest and principal. The monthly payment A (AI-PAYMENT) is
      * computed by the JS reference and passed in. Per period:
      * interest = round(balance * i), principal = A - interest. The
      * LAST period absorbs the remaining principal so the ending
      * balance is exactly 0 (M5 DoD 2).
      * stdin (LINE SEQUENTIAL) -> stdout. Layout: copybook/amort-io.cpy.
      * Rounding authority: ROUNDED MODE IS NEAREST-EVEN.
      *****************************************************************
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
      *    device-name mapping (KEYBOARD) is an MF extension and is
      *    disabled under -std=cobol2014; bind stdin explicitly. NOTE:
      *    GnuCOBOL re-opens this path, so stdin must be a real file
      *    (shell redirect / fd), not a pipe (pipe -> status 30).
      *    Output goes through DISPLAY (direct stdout stream, pipe-safe).
           SELECT AMORT-IN  ASSIGN TO "/dev/stdin"
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-IN-STATUS.
       DATA DIVISION.
       FILE SECTION.
       FD  AMORT-IN.
       01  IN-RAW               PIC X(67).
       WORKING-STORAGE SECTION.
       COPY "copybook/amort-io.cpy".
       01  WS-IN-STATUS         PIC XX.
       01  WS-EOF               PIC 9(01) VALUE 0.
       01  WS-K                 PIC 9(03) COMP.
       01  WS-N                 PIC 9(03) COMP.
      *    balance*num up to 18+9=27 digits -> S9(31) to avoid overflow
       01  WS-PROD              PIC S9(31) PACKED-DECIMAL.
       01  WS-BAL               PIC S9(18) PACKED-DECIMAL.
       01  WS-INT               PIC S9(18) PACKED-DECIMAL.
       01  WS-PRIN              PIC S9(18) PACKED-DECIMAL.
       01  WS-PAY               PIC S9(18) PACKED-DECIMAL.
       01  WS-PAY-OUT           PIC S9(18) PACKED-DECIMAL.
       PROCEDURE DIVISION.
       MAIN-PARA.
           OPEN INPUT AMORT-IN.
           IF WS-IN-STATUS NOT = "00"
               DISPLAY "AMORT: OPEN stdin failed, status "
                   WS-IN-STATUS UPON SYSERR
               STOP RUN WITH ERROR STATUS 8
           END-IF.
           PERFORM UNTIL WS-EOF = 1
               READ AMORT-IN INTO AMORT-IN-REC
                   AT END
                       MOVE 1 TO WS-EOF
                   NOT AT END
                       PERFORM PROCESS-LOAN
               END-READ
      *        any status other than ok/EOF must abort, never spin
               IF WS-IN-STATUS NOT = "00" AND WS-IN-STATUS NOT = "10"
                   DISPLAY "AMORT: READ failed, status "
                       WS-IN-STATUS UPON SYSERR
                   STOP RUN WITH ERROR STATUS 8
               END-IF
           END-PERFORM.
           CLOSE AMORT-IN.
           STOP RUN.
      *
       PROCESS-LOAN.
           MOVE AI-PRINCIPAL TO WS-BAL.
           MOVE AI-PAYMENT   TO WS-PAY.
           MOVE AI-PERIODS   TO WS-N.
           PERFORM VARYING WS-K FROM 1 BY 1 UNTIL WS-K > WS-N
      *        interest = balance * num / den, banker's rounding
               COMPUTE WS-PROD = WS-BAL * AI-RATE-NUM
               COMPUTE WS-INT ROUNDED MODE IS NEAREST-EVEN =
                   WS-PROD / AI-RATE-DEN
                   ON SIZE ERROR
                       DISPLAY "AMORT: interest overflows S9(18)"
                           UPON SYSERR
                       STOP RUN WITH ERROR STATUS 8
               END-COMPUTE
               IF WS-K = WS-N
      *            last period: absorb remaining principal
                   MOVE WS-BAL TO WS-PRIN
               ELSE
      *            principal = clamp(A - interest, 0, balance) —
      *            copybook semantics: never negative, never over-pay;
      *            keeps every output field unsigned and both sides
      *            (JS reference / COBOL) byte-identical for any A
                   COMPUTE WS-PRIN = WS-PAY - WS-INT
                   IF WS-PRIN < 0
                       MOVE 0 TO WS-PRIN
                   END-IF
                   IF WS-PRIN > WS-BAL
                       MOVE WS-BAL TO WS-PRIN
                   END-IF
               END-IF
               COMPUTE WS-PAY-OUT = WS-PRIN + WS-INT
                   ON SIZE ERROR
                       DISPLAY "AMORT: payment overflows S9(18)"
                           UPON SYSERR
                       STOP RUN WITH ERROR STATUS 8
               END-COMPUTE
               SUBTRACT WS-PRIN FROM WS-BAL
               MOVE AI-LOAN-ID TO AO-LOAN-ID
               MOVE WS-K       TO AO-PERIOD
               MOVE WS-PAY-OUT TO AO-PAYMENT
               MOVE WS-INT     TO AO-INTEREST
               MOVE WS-PRIN    TO AO-PRINCIPAL
               MOVE WS-BAL     TO AO-BALANCE
               DISPLAY AMORT-OUT-REC
           END-PERFORM.
