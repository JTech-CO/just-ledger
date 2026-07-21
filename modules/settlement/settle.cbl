       IDENTIFICATION DIVISION.
       PROGRAM-ID. SETTLE.
      *****************************************************************
      * Month-end settlement: convert each multi-currency entry to KRW
      * minor units (banker's rounding) and aggregate net balance per
      * account (debit - credit). stdin (LINE SEQUENTIAL) -> stdout.
      * Record layout: copybook/settle-io.cpy (single source of truth).
      *
      * INV-7: this output must match the JS reference implementation
      * (scripts/parity/lib.mjs) to the won; any 1-won difference blocks
      * settlement. Rounding authority: ROUNDED MODE IS NEAREST-EVEN.
      *****************************************************************
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
      *    device-name mapping (KEYBOARD) is an MF extension and is
      *    disabled under -std=cobol2014; bind stdin explicitly. NOTE:
      *    GnuCOBOL re-opens this path, so stdin must be a real file
      *    (shell redirect / fd), not a pipe (pipe -> status 30).
      *    Output goes through DISPLAY (direct stdout stream, pipe-safe).
           SELECT SETTLE-IN  ASSIGN TO "/dev/stdin"
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-IN-STATUS.
       DATA DIVISION.
       FILE SECTION.
       FD  SETTLE-IN.
       01  IN-RAW               PIC X(81).
       WORKING-STORAGE SECTION.
       COPY "copybook/settle-io.cpy".
       01  WS-IN-STATUS         PIC XX.
       01  WS-EOF               PIC 9(01) VALUE 0.
       01  WS-FOUND             PIC 9(01).
       01  WS-IDX               PIC 9(05) COMP.
      *    product = amount(15) * num(15) up to 30 digits -> S9(31)
       01  WS-PROD              PIC S9(31) PACKED-DECIMAL.
       01  WS-KRW               PIC S9(18) PACKED-DECIMAL.
       01  WS-SIGNED            PIC S9(18) PACKED-DECIMAL.
       01  ACC-COUNT            PIC 9(05) COMP VALUE 0.
       01  ACC-TABLE.
           05  ACC-ENTRY OCCURS 1 TO 5000 TIMES
                         DEPENDING ON ACC-COUNT
                         ASCENDING KEY IS ACC-CODE.
               10  ACC-CODE     PIC X(32).
               10  ACC-BAL      PIC S9(18) PACKED-DECIMAL.
       PROCEDURE DIVISION.
       MAIN-PARA.
           OPEN INPUT SETTLE-IN.
           IF WS-IN-STATUS NOT = "00"
               DISPLAY "SETTLE: OPEN stdin failed, status "
                   WS-IN-STATUS UPON SYSERR
               STOP RUN WITH ERROR STATUS 8
           END-IF.
           PERFORM UNTIL WS-EOF = 1
               READ SETTLE-IN INTO SETTLE-IN-REC
                   AT END
                       MOVE 1 TO WS-EOF
                   NOT AT END
                       PERFORM ACCUMULATE-ONE
               END-READ
      *        any status other than ok/EOF must abort, never spin
               IF WS-IN-STATUS NOT = "00" AND WS-IN-STATUS NOT = "10"
                   DISPLAY "SETTLE: READ failed, status "
                       WS-IN-STATUS UPON SYSERR
                   STOP RUN WITH ERROR STATUS 8
               END-IF
           END-PERFORM.
           PERFORM EMIT-BALANCES.
           CLOSE SETTLE-IN.
           STOP RUN.
      *
       ACCUMULATE-ONE.
      *    KRW conversion: amount * num / den, banker's rounding.
      *    amount and num are non-negative; sign is DIRECTION.
           COMPUTE WS-PROD = SI-AMOUNT * SI-RATE-NUM.
           COMPUTE WS-KRW ROUNDED MODE IS NEAREST-EVEN =
               WS-PROD / SI-RATE-DEN.
           IF SI-DIRECTION = "C"
               COMPUTE WS-SIGNED = 0 - WS-KRW
           ELSE
               MOVE WS-KRW TO WS-SIGNED
           END-IF.
      *    accumulate per account (linear probe; append if new)
           MOVE 0 TO WS-FOUND.
           PERFORM VARYING WS-IDX FROM 1 BY 1
                   UNTIL WS-IDX > ACC-COUNT OR WS-FOUND = 1
               IF ACC-CODE(WS-IDX) = SI-ACCOUNT-CODE
                   ADD WS-SIGNED TO ACC-BAL(WS-IDX)
                   MOVE 1 TO WS-FOUND
               END-IF
           END-PERFORM.
           IF WS-FOUND = 0
               ADD 1 TO ACC-COUNT
               MOVE SI-ACCOUNT-CODE TO ACC-CODE(ACC-COUNT)
               MOVE WS-SIGNED       TO ACC-BAL(ACC-COUNT)
           END-IF.
      *
       EMIT-BALANCES.
      *    sort accounts ascending by code, then emit balances on stdout
           IF ACC-COUNT > 0
               SORT ACC-ENTRY ASCENDING KEY ACC-CODE
               PERFORM VARYING WS-IDX FROM 1 BY 1
                       UNTIL WS-IDX > ACC-COUNT
                   MOVE ACC-CODE(WS-IDX) TO SO-ACCOUNT-CODE
                   MOVE ACC-BAL(WS-IDX)  TO SO-BALANCE-KRW
                   DISPLAY SETTLE-OUT-REC
               END-PERFORM
           END-IF.
