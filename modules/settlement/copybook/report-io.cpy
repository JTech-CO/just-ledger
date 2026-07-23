      *****************************************************************
      * report-io.cpy — settlement summary report INPUT records (SSOT)
      *
      * Single source of truth (with contracts/*.schema.json) for the
      * report batch input layout. The JS reference (records.mjs) mirrors
      * this layout to emit the golden input; if it changes, fix the
      * contract first and report it.
      *
      * The report driver reads a header/detail record stream and renders
      * a fixed-width text document to stdout (control-break style: one
      * header, then detail rows). The rendered document is presentation
      * for the FixedWidthReport viewer, so its line layout lives in the
      * program (report.cbl WORKING-STORAGE), not here — this copybook
      * only pins the wire records the generator produces.
      *
      * Files are LINE SEQUENTIAL. Record type lives in column 1:
      *   'H' header — reporting period and title.
      *   'D' detail — one account: code, name, net balance.
      * Contract: the FIRST record is the single 'H'; every following
      * record is 'D'. report.cbl aborts (ERROR STATUS 8) on a missing
      * header, an out-of-place header, or an unknown record type — no
      * silent skipping.
      *
      * RD-BALANCE is PIC S9(18) SIGN LEADING SEPARATE — byte-for-byte the
      * same encoding as SETTLE-OUT-REC.SO-BALANCE-KRW (settle-io.cpy), so
      * settlement output rows feed the report directly once an account
      * name is attached. Amounts are minor-unit integers (INV-4). The net
      * total is accumulated in wider precision and must fit PIC S9(18);
      * overflow aborts via range check (no silent truncation).
      *****************************************************************

      * ── Input record: header OR detail (length = 76) ────────────────
      * A short header line (48 chars on the wire) is space-filled to the
      * record width on READ; column 1 disambiguates the two views below.
       01  REPORT-IN-REC.
           05  RI-REC-TYPE          PIC X(01).
           05  RI-BODY              PIC X(75).

      * ── Header view ('H'): period + report title (natural len 48) ───
       01  REPORT-HDR REDEFINES REPORT-IN-REC.
           05  FILLER               PIC X(01).
           05  RH-PERIOD            PIC X(07).
      *        reporting period, 'YYYY-MM'
           05  RH-TITLE             PIC X(40).
      *        free-text report title / ledger name
           05  FILLER               PIC X(28).

      * ── Detail view ('D'): one account balance (len 76) ─────────────
       01  REPORT-DTL REDEFINES REPORT-IN-REC.
           05  FILLER               PIC X(01).
           05  RD-CODE              PIC X(32).
           05  RD-NAME              PIC X(24).
           05  RD-BALANCE           PIC S9(18) SIGN LEADING SEPARATE.
      *        net KRW balance (debit +, credit -), minor units.
      *        19 bytes: sign 1 + 18 digits.
