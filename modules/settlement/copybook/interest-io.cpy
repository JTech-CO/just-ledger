      *****************************************************************
      * interest-io.cpy — interest accrual batch I/O records (SSOT)
      *
      * Single source of truth (with contracts/*.schema.json) for the
      * interest batch layout. The JS reference (scripts/parity/lib.mjs,
      * records.mjs) mirrors this layout instead of redefining it; if the
      * layout changes, fix the contract first and report it.
      *
      * I/O is DISPLAY fixed-width text so bytes are explicit and platform
      * independent (golden regression). PACKED-DECIMAL is used only for
      * intermediate WORKING-STORAGE arithmetic, never on the wire.
      * Files are LINE SEQUENTIAL — records are newline delimited with no
      * trailing FILLER (record length = sum of field widths).
      *
      * Amounts are minor-unit integers. Rates are rational pairs num/den
      * (no floating point, INV-4). Rounding authority is the COBOL
      * ROUNDED MODE IS NEAREST-EVEN (banker's rounding) — the same single
      * rounding rule the whole module shares. This program reproduces the
      * JS reference to the won; a 1-won difference blocks settlement.
      *
      * ── Two accrual methods (II-METHOD selects) ─────────────────────
      * 'S' simple day-count accrual (deposit / overdue interest):
      *     interest = round_half_even(principal * rate_num * days,
      *                                rate_den * basis)
      *     one rounding; DAYS is the accrual span, BASIS the day-count
      *     divisor (e.g. 00365 actual/365, 00360 30/360).
      * 'C' compound per-period accrual (term deposit / rollover):
      *     balance starts at principal; for each of PERIODS periods
      *         period_interest = round_half_even(balance * rate_num,
      *                                           rate_den)
      *         balance = balance + period_interest
      *     interest credited and ROUNDED every period (bank practice),
      *     so rate_num/rate_den is the PER-PERIOD rate. total interest
      *     = ending balance - principal.
      *
      * ── Contract limits (enforced by generator and COBOL both) ──────
      * 1. II-METHOD is 'S' or 'C' only; COBOL aborts (ERROR STATUS 8)
      *    on anything else — no silent method guessing.
      * 2. II-RATE-DEN > 0 always (divisor). For 'S', II-BASIS > 0 too.
      *    A zero divisor aborts before any division.
      * 3. Accrued interest and ending balance fit PIC 9(15). Overflow is
      *    caught by ON SIZE ERROR and aborts (ERROR STATUS 8); there is
      *    no silent truncation path.
      *****************************************************************

      * ── Input record: one deposit / loan accrual (length = 63) ──────
       01  INTEREST-IN-REC.
           05  II-ACCOUNT-ID        PIC X(16).
           05  II-METHOD            PIC X(01).
      *        'S' simple day-count / 'C' compound per-period
           05  II-PRINCIPAL         PIC 9(15).
      *        principal, minor-unit positive integer
           05  II-RATE-NUM          PIC 9(09).
           05  II-RATE-DEN          PIC 9(09).
      *        'S': annual (or stated) rate num/den. 'C': per-period rate.
           05  II-DAYS              PIC 9(05).
      *        'S' only: accrual span in days. 'C': ignored (zero-filled).
           05  II-BASIS             PIC 9(05).
      *        'S' only: day-count basis divisor. 'C': ignored.
           05  II-PERIODS           PIC 9(03).
      *        'C' only: number of compounding periods. 'S': ignored.

      * ── Output record: accrued interest per account (length = 62) ───
       01  INTEREST-OUT-REC.
           05  IO-ACCOUNT-ID        PIC X(16).
           05  IO-METHOD            PIC X(01).
           05  IO-PRINCIPAL         PIC 9(15).
           05  IO-INTEREST          PIC 9(15).
      *        total interest accrued over the period, minor units
           05  IO-BALANCE           PIC 9(15).
      *        principal + interest (ending balance), minor units
