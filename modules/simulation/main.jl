# modules/simulation/main.jl — Julia 시뮬레이션 모듈 (M6, 기술 백서 §4.3)
#
# 프로토콜: JSONL stdin → JSONL stdout, 라인 1:1 대응.
#   잘못된 줄은 {"ok":false,"error":"..."} 한 줄로 응답하고 다음 줄을 계속 처리한다.
#   출력에 타임스탬프·비결정 값 금지. 확률·실수 값은 고정 자릿수 "문자열"로만
#   직렬화한다(Float 직렬화 편차 차단). 금액은 최소 화폐 단위 정수 문자열(JSON 경계).
#   부동소수점은 통계 계산 내부에만 허용하고, 금액 산출은 정수로 환원한다(전역 규칙).
#
# 결정론(M6 DoD 1): RNG 는 요청의 seed 로 Random.Xoshiro 를 명시 생성한다.
#   전역 RNG 를 쓰지 않으며, 고정 시드에서 재실행 시 stdout 이 바이트 단위로 동일하다.
#
# 캐시(M6 DoD 5): --cache-dir <dir> 지정 시 stdin 전체 바이트의 SHA-256 을 키로
#   stdout 전문을 <key>.out 에 저장한다. 히트 시 재계산 없이 그 바이트를 그대로
#   출력하고 stderr 에만 "cache hit <key>" 를 남긴다(stdout 은 캐시 유무와 무관하게 동일).

using JSON3
using Printf
using Random
using SHA
using Statistics
using StatsBase

# ── 공통 ────────────────────────────────────────────────────────────────────

struct SimError <: Exception
    msg::String
end

# 계약 moneyMinor 와 동일 수용 집합: 최대 18자리, 선행 0 금지, 부호는 '-' 만.
const MONEY_RE = r"^-?(0|[1-9][0-9]{0,17})$"

# 2^53 — Float64 가 정수를 정확히 표현하는 한계.
const MAX_EXACT_FLOAT = Int64(9007199254740992)

# 통계 경로(Float64 경유)에 들어가는 금액의 정밀도 가드.
# 계약(moneyMinor)은 18자리까지 허용하므로 Float64 로 내리면 하위 비트가 조용히
# 잘린다. R 모듈(anomaly.R amounts_to_numeric)은 같은 값을 명시 거절하므로
# 두 모듈의 계약을 대칭으로 맞춘다 — 침묵 손실 금지(INV-4 정신).
function check_stat_range(v::Int64, field::AbstractString)::Int64
    abs(v) > MAX_EXACT_FLOAT &&
        throw(SimError("$field: 2^53 초과 금액은 통계 경로에서 다룰 수 없습니다"))
    return v
end

function parse_money(v, field::AbstractString; allow_negative::Bool)::Int64
    v isa AbstractString || throw(SimError("$field 는 정수 문자열이어야 함"))
    occursin(MONEY_RE, v) || throw(SimError("$field 형식 오류 (최소 화폐 단위 정수 문자열)"))
    if !allow_negative && startswith(v, "-")
        throw(SimError("$field 는 음수 불가"))
    end
    return parse(Int64, v)
end

function req_field(obj, key::Symbol)
    v = get(obj, key, nothing)
    v === nothing && throw(SimError("$key 누락"))
    return v
end

function req_int(obj, key::Symbol, lo::Integer, hi::Integer)::Int64
    v = req_field(obj, key)
    (v isa Integer && !(v isa Bool)) || throw(SimError("$key 는 정수여야 함"))
    x = Int64(v)
    lo <= x <= hi || throw(SimError("$key 범위 오류 ($lo..$hi)"))
    return x
end

err_json(msg::AbstractString) = JSON3.write((ok = false, error = String(msg)))

# ── montecarlo — 가우시안 KDE 리샘플링 몬테카를로 (백서 §4.3) ────────────────

# 분위수 type=1 상당: 보간 없이 표본값 자체를 선택한다. pct 는 정수 퍼센트(5, 25, …) —
# p*n 의 부동소수점 경계 오차를 피하려고 인덱스를 정수 산술(cld)로 만든다.
function quantile_type1(sorted::Vector{Float64}, pct::Int)::Float64
    n = length(sorted)
    return sorted[clamp(cld(pct * n, 100), 1, n)]
end

# 표시용 정수 환원(floor).
# 주의: 이 값은 몬테카를로 '추정치'의 표시 규약일 뿐 원장 금액이 아니다.
#       원장 반올림 정본은 COBOL NEAREST-EVEN 하나이며(전역 규칙), 여기서 그것을
#       구현·대체하지 않는다 — floor 는 시뮬레이션 표시 규약으로만 쓴다.
function floor_display_minor(x::Float64)::Int64
    isfinite(x) || throw(SimError("발산"))
    f = floor(x)
    -9.0e18 <= f <= 9.0e18 || throw(SimError("발산"))
    return Int64(f)
end

function run_montecarlo(seed::Int64, iterations::Int64, horizon::Int64,
                        initial::Int64, hist::Vector{Float64})
    n = length(hist)
    # 가우시안 KDE 샘플링 직접 구현: 관측치 리샘플 + 대역폭 노이즈.
    # 실버만 대역폭 bw = 0.9 · min(sd, IQR/1.34) · n^(-1/5)
    spread = min(std(hist), iqr(hist) / 1.34)
    bw = 0.9 * spread * Float64(n)^(-0.2)
    isfinite(bw) || throw(SimError("발산"))

    rng = Xoshiro(seed)            # 전역 RNG 금지 — 결정론 (M6 DoD 1)
    init = Float64(initial)
    finals = Vector{Float64}(undef, iterations)
    depleted = 0
    finite_ok = true
    for i in 1:iterations
        bal = init
        hit = bal < 0.0
        for _ in 1:horizon
            net = rand(rng, hist) + bw * randn(rng)
            bal += net
            finite_ok &= isfinite(bal)
            hit |= bal < 0.0
        end
        finals[i] = bal
        depleted += hit ? 1 : 0
    end
    # 모든 경로 값 isfinite 검증 — 하나라도 NaN/Inf 면 거절 (M6 DoD 3)
    finite_ok || throw(SimError("발산"))

    p = depleted / iterations
    ci = 1.96 * sqrt(p * (1.0 - p) / iterations)
    sort!(finals)
    quants = (
        p05 = string(floor_display_minor(quantile_type1(finals, 5))),
        p25 = string(floor_display_minor(quantile_type1(finals, 25))),
        p50 = string(floor_display_minor(quantile_type1(finals, 50))),
        p75 = string(floor_display_minor(quantile_type1(finals, 75))),
        p95 = string(floor_display_minor(quantile_type1(finals, 95))),
    )
    # 확률·실수는 고정 자릿수 문자열로만 — Float 직렬화 편차 차단
    return (@sprintf("%.4f", p), @sprintf("%.6f", ci), quants)
end

function handle_montecarlo(obj)::String
    seed = req_int(obj, :seed, 0, typemax(Int64))   # seed 없으면 "seed 누락" 오류
    iterations = haskey(obj, :iterations) ? req_int(obj, :iterations, 1, 1_000_000) : Int64(10_000)
    horizon = req_int(obj, :horizon_months, 1, 120)
    initial = check_stat_range(
        parse_money(req_field(obj, :initial_balance_minor), "initial_balance_minor";
                    allow_negative = true), "initial_balance_minor")
    hist_raw = req_field(obj, :monthly_net_minor_history)
    hist_raw isa AbstractVector || throw(SimError("monthly_net_minor_history 는 배열이어야 함"))
    length(hist_raw) >= 6 || throw(SimError("monthly_net_minor_history 는 6개 이상 필요"))
    # 금액 문자열 → 정수 검증 → 통계 내부에서만 Float64 사용
    hist = Float64[Float64(check_stat_range(
                       parse_money(x, "monthly_net_minor_history[]"; allow_negative = true),
                       "monthly_net_minor_history[]"))
                   for x in hist_raw]

    dp, ci, quants = run_montecarlo(seed, iterations, horizon, initial, hist)
    return JSON3.write((
        ok = true,
        kind = "montecarlo",
        depletion_probability = dp,
        ci95_halfwidth = ci,
        final_balance_quantiles = quants,
        iterations = iterations,
        horizon_months = horizon,
    ))
end

# ── repayment — 상환 순서 전수 최적화 (백서 §4.3) ────────────────────────────

const MAX_MONTHS = 1200
# 이 한도를 넘는 잔액은 예산으로 회복 불가능한 발산으로 판정한다
# (입력 잔액 ≤ 18자리(1e18), 잔액은 이자 > 지불일 때만 증가 — 이자는 잔액에 단조라
#  한 번 예산을 넘어선 이자는 되돌아오지 못한다). Int128 오버플로 방지 겸용:
#  한도(1e22) × rate_num(≤1e9) = 1e31 ≪ typemax(Int128) ≈ 1.7e38.
const BAL_DIVERGE_LIMIT = Int128(10)^22

function lex_less(a::Vector{String}, b::Vector{String})::Bool
    for i in 1:min(length(a), length(b))
        a[i] < b[i] && return true
        b[i] < a[i] && return false
    end
    return length(a) < length(b)
end

function permutations_indices(n::Int)::Vector{Vector{Int}}
    out = Vector{Vector{Int}}()
    used = falses(n)
    cur = Int[]
    function rec()
        if length(cur) == n
            push!(out, copy(cur))
            return
        end
        for i in 1:n
            used[i] && continue
            used[i] = true
            push!(cur, i)
            rec()
            pop!(cur)
            used[i] = false
        end
    end
    rec()
    return out
end

# 한 우선순위 순서를 완제까지 시뮬레이션한다.
# 반환: (months, total_interest, total_paid).
# 완제 불가(1200개월 초과·발산)거나 가지치기(interest_limit 초과)면 nothing.
function simulate_order(order::Vector{Int}, bals0::Vector{Int128}, nums::Vector{Int128},
                        dens::Vector{Int128}, mins::Vector{Int128}, budget::Int128,
                        interest_limit::Union{Nothing,Int128})
    bals = copy(bals0)
    total_interest = Int128(0)
    total_paid = Int128(0)
    months = 0
    while any(>(Int128(0)), bals)
        months += 1
        months > MAX_MONTHS && return nothing
        # 1) 이자 가산 — 월 이자 = cld(잔액 × rate_num, rate_den) (올림 나눗셈).
        #    보수적(과대) 추정 규약이며 원장 반올림이 아니다 — 원장 반올림 정본은
        #    COBOL NEAREST-EVEN 하나이고, 이 모듈은 원장 금액을 만들지 않는다.
        for k in eachindex(bals)
            if bals[k] > 0
                interest = cld(bals[k] * nums[k], dens[k])
                bals[k] += interest
                total_interest += interest
                bals[k] > BAL_DIVERGE_LIMIT && return nothing
            end
        end
        # 가지치기: 총이자는 단조 증가 — 이미 최적 후보를 초과하면 이 순서는 탈락.
        # 동률(==)은 사전순 타이브레이크 대상이므로 '초과'일 때만 중단한다.
        interest_limit !== nothing && total_interest > interest_limit && return nothing
        # 2) 전 부채 최소상환 — 잔액 초과분은 잔액으로 클램프.
        #    완제 부채는 지급 0 → 그 최소상환분이 예산에 자동 환류된다.
        left = budget
        for k in eachindex(bals)
            pay = min(mins[k], bals[k])
            bals[k] -= pay
            left -= pay
            total_paid += pay
        end
        # 3) 잔여 예산을 우선순위 순서대로 몰아주기 (스노볼 구조)
        for k in order
            left <= 0 && break
            pay = min(left, bals[k])
            bals[k] -= pay
            left -= pay
            total_paid += pay
        end
    end
    return (months, total_interest, total_paid)
end

# 부채 ≤ 8 → 모든 우선순위 순열을 전수 시뮬레이션하고 총이자 최소 순서를 고른다.
# 동률이면 id 배열 사전순으로 결정론을 보장한다 (M6 DoD 1).
function optimize_repayment(ids::Vector{String}, bals::Vector{Int128}, nums::Vector{Int128},
                            dens::Vector{Int128}, mins::Vector{Int128}, budget::Int128)
    best_interest = nothing
    best_ids = String[]
    best_months = 0
    best_paid = Int128(0)
    for perm in permutations_indices(length(ids))
        r = simulate_order(perm, bals, nums, dens, mins, budget, best_interest)
        r === nothing && continue
        months, interest, paid = r
        perm_ids = String[ids[k] for k in perm]
        if best_interest === nothing || interest < best_interest ||
           (interest == best_interest && lex_less(perm_ids, best_ids))
            best_interest = interest
            best_ids = perm_ids
            best_months = months
            best_paid = paid
        end
    end
    best_interest === nothing && throw(SimError("발산: 1200개월 초과"))
    return (best_ids, best_months, best_interest, best_paid)
end

function handle_repayment(obj)::String
    budget = Int128(parse_money(req_field(obj, :budget_minor), "budget_minor";
                                allow_negative = false))
    debts_raw = req_field(obj, :debts)
    debts_raw isa AbstractVector || throw(SimError("debts 는 배열이어야 함"))
    1 <= length(debts_raw) <= 8 || throw(SimError("debts 는 1..8개여야 함"))

    ids = String[]
    bals = Int128[]
    nums = Int128[]
    dens = Int128[]
    mins = Int128[]
    for d in debts_raw
        d isa JSON3.Object || throw(SimError("debts[] 는 객체여야 함"))
        id = req_field(d, :id)
        (id isa AbstractString && !isempty(id) && length(id) <= 64) ||
            throw(SimError("debts[].id 형식 오류"))
        String(id) in ids && throw(SimError("debts[].id 중복"))
        push!(ids, String(id))
        push!(bals, Int128(parse_money(req_field(d, :balance_minor), "debts[].balance_minor";
                                       allow_negative = false)))
        push!(nums, Int128(req_int(d, :rate_num, 0, 1_000_000_000)))
        push!(dens, Int128(req_int(d, :rate_den, 1, 1_000_000_000)))
        push!(mins, Int128(parse_money(req_field(d, :min_payment_minor), "debts[].min_payment_minor";
                                       allow_negative = false)))
    end
    sum(mins) <= budget || throw(SimError("budget 이 최소상환 합보다 작음"))

    order_ids, months, interest, paid = optimize_repayment(ids, bals, nums, dens, mins, budget)
    return JSON3.write((
        ok = true,
        kind = "repayment",
        order = order_ids,
        months = months,
        total_interest_minor = string(interest),
        total_paid_minor = string(paid),
    ))
end

# ── warmup — 워커 기동 JIT 예열 (모듈 CLAUDE.md) ─────────────────────────────

function handle_warmup()::String
    # 실제 핸들러와 동일한 코드 경로를 소형 입력으로 실행해 JIT 를 예열하고 결과는 버린다.
    hist = Float64[120000, -80000, 150000, -40000, 90000, -60000,
                   200000, -110000, 70000, -30000, 130000, -50000]
    run_montecarlo(Int64(1), Int64(100), Int64(12), Int64(1_000_000), hist)
    optimize_repayment(["w1", "w2"],
                       Int128[100000, 50000], Int128[1, 2], Int128[100, 100],
                       Int128[10000, 5000], Int128(90000))
    return JSON3.write((ok = true, kind = "warmup"))
end

# ── 디스패치·프로토콜 ────────────────────────────────────────────────────────

function handle_line(line::AbstractString)::String
    obj = try
        JSON3.read(line)
    catch
        return err_json("잘못된 JSON")
    end
    return try
        obj isa JSON3.Object || throw(SimError("JSON 객체가 아님"))
        kind = get(obj, :kind, nothing)
        kind === nothing && throw(SimError("kind 누락"))
        if kind == "montecarlo"
            handle_montecarlo(obj)
        elseif kind == "repayment"
            handle_repayment(obj)
        elseif kind == "warmup"
            handle_warmup()
        else
            throw(SimError("알 수 없는 kind"))
        end
    catch e
        e isa SimError ? err_json(e.msg) :
            err_json("내부 오류: " * first(sprint(showerror, e), 200))
    end
end

function process(text::AbstractString)::Vector{UInt8}
    out = IOBuffer()
    lines = split(text, '\n')
    # 마지막 개행 뒤의 빈 조각은 줄이 아니다 (라인 1:1 대응 유지)
    if !isempty(lines) && isempty(last(lines))
        pop!(lines)
    end
    for raw in lines
        line = endswith(raw, '\r') ? chop(raw) : raw
        write(out, handle_line(line))
        write(out, UInt8('\n'))
    end
    return take!(out)
end

function main()
    cache_dir = nothing
    i = 1
    while i <= length(ARGS)
        if ARGS[i] == "--cache-dir" && i < length(ARGS)
            cache_dir = ARGS[i + 1]
            i += 2
        else
            println(stderr, "사용법: main.jl [--cache-dir <dir>]")
            exit(2)
        end
    end

    input = read(stdin)                                   # stdin 전체 바이트 (캐시 키 대상)
    key = cache_dir === nothing ? nothing : bytes2hex(sha256(input))

    if key !== nothing
        path = joinpath(cache_dir, key * ".out")
        if isfile(path)
            # 캐시 히트: 저장된 stdout 전문을 재계산 없이 그대로 출력 (M6 DoD 5).
            # stdout 은 캐시 유무와 무관하게 바이트 동일해야 하므로 표기는 stderr 에만.
            write(stdout, read(path))
            println(stderr, "cache hit ", key)
            return
        end
    end

    data = process(String(input))
    if key !== nothing
        mkpath(cache_dir)
        write(joinpath(cache_dir, key * ".out"), data)
    end
    write(stdout, data)
end

main()
