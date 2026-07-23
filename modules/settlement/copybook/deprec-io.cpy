      *****************************************************************
      * deprec-io.cpy — fixed-asset depreciation batch I/O records (SSOT)
      *
      * Single source of truth (with contracts/*.schema.json) for the
      * depreciation batch layout. The JS reference (scripts/parity/
      * lib.mjs, records.mjs) mirrors this layout; if it changes, fix the
      * contract first and report it.
      *
      * Unlike loan amortization (amort-io.cpy), which splits a fixed
      * payment into interest and principal, this program writes an
      * asset's book value DOWN over its useful life to a salvage floor —
      * the depreciation posted at each period close. I/O is DISPLAY
      * fixed-width text; PACKED-DECIMAL is used only for intermediate
      * arithmetic. Amounts are minor-unit integers, rates are rational
      * num/den (no floating point, INV-4). Rounding is the module-wide
      * ROUNDED MODE IS NEAREST-EVEN.
      *
      * ── Two depreciation methods (DI-METHOD selects) ────────────────
      * 'L' straight-line: each period depreciation =
      *        round_half_even(cost - salvage, periods).
      * 'D' declining-balance: each period depreciation =
      *        round_half_even(book_value * rate_num, rate_den),
      *        clamped so book value never falls below salvage.
      * Both methods absorb the remainder in the LAST period so the
      * ending book value is exactly the salvage value (parallels the
      * amort schedule ending at exactly zero). Once an asset is fully
      * depreciated the remaining periods post depreciation 0. Every
      * output value is >= 0 (unsigned PIC 9).
      *
      * ── Contract limits (enforced by generator and COBOL both) ──────
      * 1. DI-METHOD is 'L' or 'D' only; COBOL aborts on anything else.
      * 2. DI-SALVAGE <= DI-COST (a negative depreciable base is a
      *    contract break); COBOL aborts otherwise. For 'D', rate_den > 0.
      * 3. DI-PERIODS is 1..360 (generator rejects out of range).
      * 4. Arithmetic beyond S9(18) aborts via ON SIZE ERROR — no silent
      *    truncation path.
      *****************************************************************

      * ── Input record: one fixed asset (length = 68) ────────────────
       01  DEPREC-IN-REC.
           05  DI-ASSET-ID          PIC X(16).
           05  DI-METHOD            PIC X(01).
      *        'L' straight-line / 'D' declining-balance
           05  DI-COST              PIC 9(15).
      *        acquisition cost, minor units
           05  DI-SALVAGE           PIC 9(15).
      *        salvage (residual) value, minor units; <= cost
           05  DI-RATE-NUM          PIC 9(09).
           05  DI-RATE-DEN          PIC 9(09).
      *        'D' only: per-period rate num/den. 'L': ignored (0-filled).
           05  DI-PERIODS           PIC 9(03).
      *        useful life in periods (1..360)

      * ── Output record: one period of the schedule (length = 64) ─────
       01  DEPREC-OUT-REC.
           05  DO-ASSET-ID          PIC X(16).
           05  DO-PERIOD            PIC 9(03).
      *        period number (1-based)
           05  DO-DEPREC            PIC 9(15).
      *        depreciation posted this period, minor units
           05  DO-ACCUM             PIC 9(15).
      *        accumulated depreciation through this period
           05  DO-BOOKVAL           PIC 9(15).
      *        ending book value (last period = salvage), minor units
