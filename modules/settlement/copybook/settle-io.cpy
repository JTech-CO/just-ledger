      *****************************************************************
      * settle-io.cpy — 마감 정산 입출력 레코드 (단일 진실원천)
      *
      * contracts/*.schema.json 과 함께 언어 간 SSOT 다. Go 고정폭 생성기와
      * JS 참조 구현(scripts/parity/lib.mjs)이 이 레이아웃을 손으로 재정의하지
      * 않고 그대로 따른다. 어긋나면 계약을 먼저 고치고 보고한다.
      *
      * 입출력은 DISPLAY(텍스트 고정폭) — 바이트가 명확하고 플랫폼 독립적이라
      * 골든 회귀에 적합하다. COMP-3 는 내부 계산(settle.cbl WORKING-STORAGE)에만
      * 쓰며, 그 바이트 재현성은 컨테이너 이미지·cobc 플래그 고정으로 담보한다.
      * 파일은 LINE SEQUENTIAL — 레코드 구분은 개행이며 트레일링 FILLER 는 두지
      * 않는다(레코드 길이 = 필드 합).
      *
      * 금액은 최소 화폐 단위 정수. 환율은 유리수 쌍 num/den (실수 없음, INV-4).
      *****************************************************************

      * ── 입력 레코드: 한 entry (레코드 길이 = 81) ──────────────────────
      * 부호는 별도 컬럼이 아니라 SI-DIRECTION('D'/'C')이 담는다.
       01  SETTLE-IN-REC.
           05  SI-ACCOUNT-CODE      PIC X(32).
           05  SI-DIRECTION         PIC X(01).
      *        'D' 차변 / 'C' 대변
           05  SI-CURRENCY          PIC X(03).
           05  SI-AMOUNT            PIC 9(15).
      *        최소 화폐 단위 양의 정수 (부호는 DIRECTION)
           05  SI-RATE-NUM          PIC 9(15).
           05  SI-RATE-DEN          PIC 9(15).
      *        해당 통화 최소단위 1 = (NUM/DEN) KRW 최소단위. KRW 는 1/1.

      * ── 출력 레코드: 계정별 마감 잔액 (레코드 길이 = 51) ───────────────
       01  SETTLE-OUT-REC.
           05  SO-ACCOUNT-CODE      PIC X(32).
           05  SO-BALANCE-KRW       PIC S9(18) SIGN LEADING SEPARATE.
      *        KRW 환산 순잔액(차변 - 대변), 최소 화폐 단위 정수.
      *        19바이트: 부호 1 + 숫자 18
