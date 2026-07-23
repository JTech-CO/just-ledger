       IDENTIFICATION DIVISION.
       PROGRAM-ID. DEPREC.
      *****************************************************************
      * Fixed-asset depreciation batch — writes each asset's book value
      * down over its useful life to a salvage floor, posting the
      * depreciation at each period close. Integer minor-unit amounts and
      * rational (num/den) rates, never touching floating point (INV-4).
      * Two methods per input record:
      *
      *   'L' straight-line: depreciation = round_half_even(
      *          cost - salvage, periods) each period.
      *   'D' declining-balance: depreciation = round_half_even(
      *          book_value * rate_num, rate_den), clamped so the book
      *          value never drops below salvage.
      *
      * Both methods absorb the remainder in the LAST period, so the
      * ending book value equals salvage exactly (parallels amort ending
      * at zero). stdin (LINE SEQUENTIAL) -> stdout. Layout: copybook/
      * deprec-io.cpy (single source of truth). Output must match the JS
      * reference (scripts/parity/lib.mjs). Rounding authority: ROUNDED
      * MODE IS NEAREST-EVEN; overflow aborts via ON SIZE ERROR.
      *****************************************************************
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
      *    Bind stdin explicitly (KEYBOARD mapping is disabled under
      *    -std=cobol2014). GnuCOBOL re-opens the path, so stdin must be a
      *    real file (shell redirect / fd), not a pipe. Output is DISPLAY
      *    (direct stdout stream, pipe-safe).
           SELECT DEPREC-IN  ASSIGN TO "/dev/stdin"
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-IN-STATUS.
       DATA DIVISION.
       FILE SECTION.
       FD  DEPREC-IN.
       01  IN-RAW               PIC X(68).
       WORKING-STORAGE SECTION.
       COPY "copybook/deprec-io.cpy".
       01  WS-IN-STATUS         PIC XX.
       01  WS-EOF               PIC 9(01) VALUE 0.
       01  WS-K                 PIC 9(03) COMP.
       01  WS-N                 PIC 9(03) COMP.
      *    book(18) * num(9) reaches 27 digits, so the product needs 31.
       01  WS-PROD              PIC S9(31) PACKED-DECIMAL.
       01  WS-BASE              PIC S9(18) PACKED-DECIMAL.
       01  WS-PER               PIC S9(18) PACKED-DECIMAL.
       01  WS-BOOK              PIC S9(18) PACKED-DECIMAL.
       01  WS-ACCUM             PIC S9(18) PACKED-DECIMAL.
       01  WS-DEP               PIC S9(18) PACKED-DECIMAL.
       01  WS-REMAIN            PIC S9(18) PACKED-DECIMAL.
       PROCEDURE DIVISION.
       MAIN-PARA.
           OPEN INPUT DEPREC-IN.
           IF WS-IN-STATUS NOT = "00"
               DISPLAY "DEPREC: OPEN stdin failed, status "
                   WS-IN-STATUS UPON SYSERR
               STOP RUN WITH ERROR STATUS 8
           END-IF.
           PERFORM UNTIL WS-EOF = 1
               READ DEPREC-IN INTO DEPREC-IN-REC
                   AT END
                       MOVE 1 TO WS-EOF
                   NOT AT END
                       PERFORM PROCESS-ASSET
               END-READ
      *        any status other than ok/EOF must abort, never spin
               IF WS-IN-STATUS NOT = "00" AND WS-IN-STATUS NOT = "10"
                   DISPLAY "DEPREC: READ failed, status "
                       WS-IN-STATUS UPON SYSERR
                   STOP RUN WITH ERROR STATUS 8
               END-IF
           END-PERFORM.
           CLOSE DEPREC-IN.
           STOP RUN.
      *
       PROCESS-ASSET.
      *    contract: method is 'L' or 'D' only; never guess (a divergent
      *    method from the JS reference is an INV-7 break).
           IF DI-METHOD NOT = "L" AND DI-METHOD NOT = "D"
               DISPLAY "DEPREC: invalid method " DI-METHOD UPON SYSERR
               STOP RUN WITH ERROR STATUS 8
           END-IF.
      *    a salvage above cost is a negative depreciable base.
           IF DI-SALVAGE > DI-COST
               DISPLAY "DEPREC: salvage exceeds cost" UPON SYSERR
               STOP RUN WITH ERROR STATUS 8
           END-IF.
      *    declining-balance divides by rate_den; a zero is malformed.
           IF DI-METHOD = "D" AND DI-RATE-DEN = 0
               DISPLAY "DEPREC: rate_den is zero (declining)"
                   UPON SYSERR
               STOP RUN WITH ERROR STATUS 8
           END-IF.
           COMPUTE WS-BASE = DI-COST - DI-SALVAGE.
           MOVE DI-COST    TO WS-BOOK.
           MOVE 0          TO WS-ACCUM.
           MOVE DI-PERIODS TO WS-N.
           IF DI-METHOD = "L"
      *        straight-line per-period amount, rounded once up front.
               COMPUTE WS-PER ROUNDED MODE IS NEAREST-EVEN =
                   WS-BASE / DI-PERIODS
                   ON SIZE ERROR
                       DISPLAY "DEPREC: straight-line amount overflow"
                           UPON SYSERR
                       STOP RUN WITH ERROR STATUS 8
               END-COMPUTE
           END-IF.
           PERFORM VARYING WS-K FROM 1 BY 1 UNTIL WS-K > WS-N
               IF WS-K = WS-N
      *            last period absorbs the remainder -> book = salvage
                   COMPUTE WS-DEP = WS-BOOK - DI-SALVAGE
               ELSE
                   PERFORM COMPUTE-PERIOD-DEP
               END-IF
               ADD WS-DEP TO WS-ACCUM
                   ON SIZE ERROR
                       DISPLAY "DEPREC: accumulated overflows S9(18)"
                           UPON SYSERR
                       STOP RUN WITH ERROR STATUS 8
               END-ADD
               SUBTRACT WS-DEP FROM WS-BOOK
               MOVE DI-ASSET-ID TO DO-ASSET-ID
               MOVE WS-K        TO DO-PERIOD
               MOVE WS-DEP      TO DO-DEPREC
               MOVE WS-ACCUM    TO DO-ACCUM
               MOVE WS-BOOK     TO DO-BOOKVAL
               DISPLAY DEPREC-OUT-REC
           END-PERFORM.
      *
       COMPUTE-PERIOD-DEP.
      *    non-final period depreciation, clamped to [0, room-to-salvage]
      *    so book value stays >= salvage and every output stays >= 0.
           IF DI-METHOD = "L"
               MOVE WS-PER TO WS-DEP
           ELSE
               COMPUTE WS-PROD = WS-BOOK * DI-RATE-NUM
               COMPUTE WS-DEP ROUNDED MODE IS NEAREST-EVEN =
                   WS-PROD / DI-RATE-DEN
                   ON SIZE ERROR
                       DISPLAY "DEPREC: declining amount overflow"
                           UPON SYSERR
                       STOP RUN WITH ERROR STATUS 8
               END-COMPUTE
           END-IF.
           IF WS-DEP < 0
               MOVE 0 TO WS-DEP
           END-IF.
           COMPUTE WS-REMAIN = WS-BOOK - DI-SALVAGE.
           IF WS-DEP > WS-REMAIN
               MOVE WS-REMAIN TO WS-DEP
           END-IF.
