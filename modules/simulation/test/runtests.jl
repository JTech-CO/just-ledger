# make test-simulation — M6 게이트 (Julia).
# T1 결정론(재실행 바이트 동일, DoD 1)  T2 골든 왕복
# T3 몬테카를로 NaN·발산 0 + CI 폭 (DoD 3)  T4 상환 최적화 정확성
# T5 캐시 (DoD 5)  T6 오류 계약  T7 프로토콜 형상
#
# main.jl 은 실행 스크립트이므로 include 하지 않고 서브프로세스로 돌린다 —
# 실제 사용자가 보는 stdin/stdout 경계 그대로를 검증한다.

using Test
using JSON3

const MOD = dirname(@__DIR__)                    # modules/simulation
const REPO = dirname(dirname(MOD))               # 저장소 루트
const MAIN = joinpath(MOD, "main.jl")
const FIX = joinpath(REPO, "fixtures", "simulation")

"main.jl 을 서브프로세스로 실행하고 (stdout 바이트, stderr 문자열) 반환"
function run_main(in_path::AbstractString; cache = nothing)
    args = String[]
    cache !== nothing && append!(args, ["--cache-dir", String(cache)])
    out = IOBuffer()
    err = IOBuffer()
    cmd = `$(Base.julia_cmd()) --project=$MOD $MAIN $args`
    run(pipeline(cmd; stdin = String(in_path), stdout = out, stderr = err))
    return (take!(out), String(take!(err)))
end

"한 줄짜리 요청을 실행하고 응답 객체를 반환"
function ask(req::AbstractString)
    p = tempname()
    write(p, req * "\n")
    bytes, _ = run_main(p)
    rm(p; force = true)
    return JSON3.read(String(bytes))
end

@testset "simulation (M6)" begin

    req_file = joinpath(FIX, "requests.jsonl")
    expected_file = joinpath(FIX, "expected.jsonl")

    @testset "T1·T2 결정론 + 골든" begin
        b1, _ = run_main(req_file)
        b2, _ = run_main(req_file)
        @test b1 == b2                                   # DoD 1 — 재실행 바이트 동일
        @test b1 == read(expected_file)                  # 저장 골든과 동일
        # 라인 1:1 대응 (마지막 개행 뒤 빈 조각 제외)
        nreq = count(!isempty, split(read(req_file, String), '\n'))
        nres = count(!isempty, split(String(b1), '\n'))
        @test nreq == nres
    end

    @testset "T3 몬테카를로 — NaN·발산 0, CI 폭 (DoD 3)" begin
        r = ask("""{"kind":"montecarlo","seed":20260722,"iterations":10000,"horizon_months":24,"initial_balance_minor":"5000000","monthly_net_minor_history":["120000","-80000","150000","-40000","90000","-60000","200000","-110000","70000","-30000","130000","-50000"]}""")
        @test r.ok === true
        @test r.iterations == 10000
        # 확률·CI 는 고정 자릿수 문자열 (Float 직렬화 편차 차단)
        @test occursin(r"^[01]\.[0-9]{4}$", r.depletion_probability)
        @test occursin(r"^[01]\.[0-9]{6}$", r.ci95_halfwidth)
        @test parse(Float64, r.ci95_halfwidth) <= 0.01   # 10,000 경로 CI 폭 기준
        # 분위수는 전부 정수 문자열이고 단조 비감소
        qs = [r.final_balance_quantiles[k] for k in (:p05, :p25, :p50, :p75, :p95)]
        @test all(q -> occursin(r"^-?[0-9]+$", q), qs)
        @test issorted(parse.(Int64, qs))
        # 같은 시드 재실행 → 완전 동일 (RNG 가 전역이 아님을 확인)
        r2 = ask("""{"kind":"montecarlo","seed":20260722,"iterations":10000,"horizon_months":24,"initial_balance_minor":"5000000","monthly_net_minor_history":["120000","-80000","150000","-40000","90000","-60000","200000","-110000","70000","-30000","130000","-50000"]}""")
        @test r2.final_balance_quantiles.p50 == r.final_balance_quantiles.p50
        # 다른 시드 → 다른 표본 (시드가 실제로 반영됨)
        r3 = ask("""{"kind":"montecarlo","seed":7,"iterations":10000,"horizon_months":24,"initial_balance_minor":"5000000","monthly_net_minor_history":["120000","-80000","150000","-40000","90000","-60000","200000","-110000","70000","-30000","130000","-50000"]}""")
        @test r3.final_balance_quantiles.p50 != r.final_balance_quantiles.p50
    end

    @testset "T4 상환 최적화" begin
        # (a) 손계산 exact — 부채 1, 잔액 100000, 월이율 1/100, 최소 50000, 예산 100000
        #  월1: 이자 cld(100000·1,100)=1000 → 잔액 101000
        #       최소 50000 → 51000, 잔여예산 50000 몰아주기 → 1000 (지급 100000)
        #  월2: 이자 cld(1000·1,100)=10 → 1010
        #       최소 min(50000,1010)=1010 → 0 (지급 1010)
        #  총이자 1010, 총지급 101010, 2개월
        r = ask("""{"kind":"repayment","budget_minor":"100000","debts":[{"id":"solo","balance_minor":"100000","rate_num":1,"rate_den":100,"min_payment_minor":"50000"}]}""")
        @test r.ok === true
        @test r.months == 2
        @test r.total_interest_minor == "1010"
        @test r.total_paid_minor == "101010"
        @test r.order == ["solo"]

        # (b) avalanche — 잔액·최소상환 동일, 이율만 다르면 고이율 우선이 최적
        r = ask("""{"kind":"repayment","budget_minor":"300000","debts":[{"id":"d-lo","balance_minor":"1000000","rate_num":5,"rate_den":1000,"min_payment_minor":"50000"},{"id":"d-hi","balance_minor":"1000000","rate_num":30,"rate_den":1000,"min_payment_minor":"50000"},{"id":"d-mid","balance_minor":"1000000","rate_num":15,"rate_den":1000,"min_payment_minor":"50000"}]}""")
        @test r.ok === true
        @test r.order == ["d-hi", "d-mid", "d-lo"]

        # (c) 완전 동률 → id 사전순으로 결정론
        r = ask("""{"kind":"repayment","budget_minor":"300000","debts":[{"id":"tie-b","balance_minor":"1000000","rate_num":10,"rate_den":1000,"min_payment_minor":"50000"},{"id":"tie-a","balance_minor":"1000000","rate_num":10,"rate_den":1000,"min_payment_minor":"50000"}]}""")
        @test r.ok === true
        @test r.order == ["tie-a", "tie-b"]

        # (d) 무이자면 총이자 0, 지급 합 = 원금 합
        r = ask("""{"kind":"repayment","budget_minor":"500000","debts":[{"id":"z1","balance_minor":"600000","rate_num":0,"rate_den":1,"min_payment_minor":"100000"},{"id":"z2","balance_minor":"400000","rate_num":0,"rate_den":1,"min_payment_minor":"100000"}]}""")
        @test r.ok === true
        @test r.total_interest_minor == "0"
        @test r.total_paid_minor == "1000000"
    end

    @testset "T5 캐시 (DoD 5)" begin
        mktempdir() do cache
            b1, e1 = run_main(req_file; cache = cache)
            b2, e2 = run_main(req_file; cache = cache)
            @test b1 == b2                               # stdout 은 캐시 유무와 무관하게 동일
            @test b1 == read(expected_file)
            @test !occursin("cache hit", e1)             # 1회째 miss
            @test occursin("cache hit", e2)              # 2회째 hit
        end
    end

    @testset "T6 오류 계약" begin
        # seed 누락 (결정론 필수 조건)
        @test ask("""{"kind":"montecarlo","iterations":100,"horizon_months":6,"initial_balance_minor":"0","monthly_net_minor_history":["1","2","3","4","5","6"]}""").ok === false
        # history 5개 (< 6)
        @test ask("""{"kind":"montecarlo","seed":1,"iterations":100,"horizon_months":6,"initial_balance_minor":"0","monthly_net_minor_history":["1","2","3","4","5"]}""").ok === false
        # 예산 < 최소상환 합
        @test ask("""{"kind":"repayment","budget_minor":"10000","debts":[{"id":"x","balance_minor":"1000000","rate_num":10,"rate_den":1000,"min_payment_minor":"50000"}]}""").ok === false
        # 발산: 최소상환이 이자를 못 따라감 → 1200개월 초과
        @test ask("""{"kind":"repayment","budget_minor":"1","debts":[{"id":"x","balance_minor":"1000000000000","rate_num":100,"rate_den":1000,"min_payment_minor":"1"}]}""").ok === false
        # 금액 형식 (선행 0·부호·소수)
        for bad in ("007", "+5", "1.5", "")
            @test ask("""{"kind":"repayment","budget_minor":"$bad","debts":[{"id":"x","balance_minor":"1000","rate_num":1,"rate_den":100,"min_payment_minor":"100"}]}""").ok === false
        end
        # id 중복 / 부채 9개 / rate_den 0
        @test ask("""{"kind":"repayment","budget_minor":"500000","debts":[{"id":"dup","balance_minor":"1000","rate_num":1,"rate_den":100,"min_payment_minor":"100"},{"id":"dup","balance_minor":"1000","rate_num":1,"rate_den":100,"min_payment_minor":"100"}]}""").ok === false
        @test ask("""{"kind":"repayment","budget_minor":"500000","debts":[{"id":"x","balance_minor":"1000","rate_num":1,"rate_den":0,"min_payment_minor":"100"}]}""").ok === false
        # 알 수 없는 kind / JSON 아님
        @test ask("""{"kind":"nope"}""").ok === false
        @test ask("""not json""").ok === false
    end

    @testset "T7 프로토콜 형상" begin
        # 잘못된 줄이 있어도 나머지 줄은 계속 처리된다 (라인 1:1)
        p = tempname()
        write(p, "not json\n{\"kind\":\"warmup\"}\nalso bad\n")
        bytes, _ = run_main(p)
        rm(p; force = true)
        lines = filter(!isempty, split(String(bytes), '\n'))
        @test length(lines) == 3
        @test JSON3.read(lines[1]).ok === false
        @test JSON3.read(lines[2]).ok === true
        @test JSON3.read(lines[3]).ok === false
        # CRLF 입력도 동일하게 처리
        p = tempname()
        write(p, "{\"kind\":\"warmup\"}\r\n")
        bytes, _ = run_main(p)
        rm(p; force = true)
        @test JSON3.read(String(bytes)).ok === true
    end
end
