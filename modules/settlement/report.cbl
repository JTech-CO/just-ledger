       IDENTIFICATION DIVISION.
       PROGRAM-ID. REPORT-SETTLE.
      *****************************************************************
      * Month-end settlement summary report — renders a header/detail
      * record stream into a fixed-width text document for the
      * FixedWidthReport viewer. Control-break style: one 'H' header
      * (period + title), then 'D' detail rows (account code, name, net
      * KRW balance). Emits a titled, ruled report with a column header,
      * one line per account, and a footer with the account count and the
      * net total.
      *
      * stdin (LINE SEQUENTIAL) -> stdout. Input layout: copybook/
      * report-io.cpy (single source of truth). RD-BALANCE is encoded
      * exactly like SETTLE-OUT-REC.SO-BALANCE-KRW, so settlement output
      * feeds this report once an account name is attached.
      *
      * All amounts are minor-unit integers formatted with numeric-edited
      * pictures (comma grouping, floating sign) — no floating point
      * (INV-4). The net total is accumulated in wider precision and range
      * checked against S9(18); overflow aborts (ERROR STATUS 8) rather
      * than truncating silently. The rendered bytes must match the JS
      * reference (scripts/parity/records.mjs formatReport).
      *****************************************************************
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
      *    Bind stdin explicitly (KEYBOARD mapping is disabled under
      *    -std=cobol2014). GnuCOBOL re-opens the path, so stdin must be a
      *    real file (shell redirect / fd), not a pipe. Output is DISPLAY
      *    (direct stdout stream, pipe-safe).
           SELECT REPORT-IN  ASSIGN TO "/dev/stdin"
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-IN-STATUS.
       DATA DIVISION.
       FILE SECTION.
       FD  REPORT-IN.
       01  IN-RAW               PIC X(76).
       WORKING-STORAGE SECTION.
       COPY "copybook/report-io.cpy".
       01  WS-IN-STATUS         PIC XX.
       01  WS-EOF               PIC 9(01) VALUE 0.
       01  WS-COUNT             PIC 9(06) VALUE 0.
      *    net total may exceed a single S9(18) balance while summing, so
      *    accumulate wide, then range-check before the edited move.
       01  WS-TOTAL             PIC S9(31) PACKED-DECIMAL VALUE 0.

      * ── Rendered report lines (86 columns, presentation) ────────────
       01  RULE-DOUBLE          PIC X(86) VALUE ALL "=".
       01  RULE-SINGLE          PIC X(86) VALUE ALL "-".
       01  TITLE-LINE.
           05  FILLER           PIC X(02) VALUE SPACES.
           05  FILLER           PIC X(84) VALUE
               "JUST-LEDGER SETTLEMENT SUMMARY".
       01  META-LINE.
           05  FILLER           PIC X(02) VALUE SPACES.
           05  FILLER           PIC X(07) VALUE "Period ".
           05  ML-PERIOD        PIC X(07).
           05  FILLER           PIC X(03) VALUE SPACES.
           05  ML-TITLE         PIC X(40).
           05  FILLER           PIC X(27) VALUE SPACES.
       01  COLHDR-LINE.
           05  FILLER           PIC X(02) VALUE SPACES.
           05  FILLER           PIC X(32) VALUE "ACCOUNT CODE".
           05  FILLER           PIC X(01) VALUE SPACES.
           05  FILLER           PIC X(24) VALUE "ACCOUNT NAME".
           05  FILLER           PIC X(27) VALUE
               "        BALANCE (KRW MINOR)".
       01  DETAIL-LINE.
           05  FILLER           PIC X(02) VALUE SPACES.
           05  DL-CODE          PIC X(32).
           05  FILLER           PIC X(01) VALUE SPACES.
           05  DL-NAME          PIC X(24).
           05  DL-BALANCE       PIC +++,+++,+++,+++,+++,+++,++9.
       01  SUMMARY-LINE.
           05  FILLER           PIC X(02) VALUE SPACES.
           05  FILLER           PIC X(10) VALUE "ACCOUNTS: ".
           05  SL-COUNT         PIC ZZZ,ZZ9.
           05  FILLER           PIC X(30) VALUE SPACES.
           05  FILLER           PIC X(09) VALUE "NET TOTAL".
           05  FILLER           PIC X(01) VALUE SPACES.
           05  SL-TOTAL         PIC +++,+++,+++,+++,+++,+++,++9.
       PROCEDURE DIVISION.
       MAIN-PARA.
           OPEN INPUT REPORT-IN.
           IF WS-IN-STATUS NOT = "00"
               DISPLAY "REPORT: OPEN stdin failed, status "
                   WS-IN-STATUS UPON SYSERR
               STOP RUN WITH ERROR STATUS 8
           END-IF.
           PERFORM READ-ONE.
      *    contract: the first record must be the single header.
           IF WS-EOF = 1
               DISPLAY "REPORT: empty input (no header)" UPON SYSERR
               STOP RUN WITH ERROR STATUS 8
           END-IF.
           IF RI-REC-TYPE NOT = "H"
               DISPLAY "REPORT: first record is not a header"
                   UPON SYSERR
               STOP RUN WITH ERROR STATUS 8
           END-IF.
           PERFORM EMIT-HEADER.
           PERFORM READ-ONE.
           PERFORM UNTIL WS-EOF = 1
               EVALUATE RI-REC-TYPE
                   WHEN "D"
                       PERFORM EMIT-DETAIL
                   WHEN OTHER
      *                a stray header or unknown type is a contract
      *                break; stop loudly instead of skipping a row.
                       DISPLAY "REPORT: unexpected record type "
                           RI-REC-TYPE UPON SYSERR
                       STOP RUN WITH ERROR STATUS 8
               END-EVALUATE
               PERFORM READ-ONE
           END-PERFORM.
           PERFORM EMIT-FOOTER.
           CLOSE REPORT-IN.
           STOP RUN.
      *
       READ-ONE.
           READ REPORT-IN INTO REPORT-IN-REC
               AT END
                   MOVE 1 TO WS-EOF
           END-READ.
           IF WS-IN-STATUS NOT = "00" AND WS-IN-STATUS NOT = "10"
               DISPLAY "REPORT: READ failed, status "
                   WS-IN-STATUS UPON SYSERR
               STOP RUN WITH ERROR STATUS 8
           END-IF.
      *
       EMIT-HEADER.
           MOVE RH-PERIOD TO ML-PERIOD.
           MOVE RH-TITLE  TO ML-TITLE.
           DISPLAY RULE-DOUBLE.
           DISPLAY TITLE-LINE.
           DISPLAY META-LINE.
           DISPLAY RULE-DOUBLE.
           DISPLAY COLHDR-LINE.
           DISPLAY RULE-SINGLE.
      *
       EMIT-DETAIL.
           ADD 1 TO WS-COUNT
               ON SIZE ERROR
                   DISPLAY "REPORT: account count overflows 9(6)"
                       UPON SYSERR
                   STOP RUN WITH ERROR STATUS 8
           END-ADD.
           ADD RD-BALANCE TO WS-TOTAL
               ON SIZE ERROR
                   DISPLAY "REPORT: net total accumulator overflow"
                       UPON SYSERR
                   STOP RUN WITH ERROR STATUS 8
           END-ADD.
           MOVE RD-CODE    TO DL-CODE.
           MOVE RD-NAME    TO DL-NAME.
           MOVE RD-BALANCE TO DL-BALANCE.
           DISPLAY DETAIL-LINE.
      *
       EMIT-FOOTER.
      *    the net total is displayed with 18 digit positions; a value
      *    beyond S9(18) would truncate in the edited move, so refuse it.
           IF WS-TOTAL > 999999999999999999
               OR WS-TOTAL < -999999999999999999
               DISPLAY "REPORT: net total overflows S9(18)"
                   UPON SYSERR
               STOP RUN WITH ERROR STATUS 8
           END-IF.
           MOVE WS-COUNT TO SL-COUNT.
           MOVE WS-TOTAL TO SL-TOTAL.
           DISPLAY RULE-SINGLE.
           DISPLAY SUMMARY-LINE.
           DISPLAY RULE-DOUBLE.
