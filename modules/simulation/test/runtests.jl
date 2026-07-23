# make test-simulation — M6 게이트 (Julia).
# T1 결정론(재실행 바이트 동일, DoD 1)  T2 골든 왕복
# T3 몬테카를로 NaN·발산 0 + CI 폭 (DoD 3)  T4 상환 최적화 정확성
# T5 캐시 (DoD 5)  T6 오류 계약  T7 프로토콜 형상  T8 통계 경로 정밀도
# T9 scenario(가정별 비교·공통 난수·base=montecarlo 불변식)
# T10 sensitivity(격자 단조성·정확 선형·threshold)  T11 scenario·sensitivity 오류 계약
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

    @testset "T8 통계 경로 정밀도 (R 모듈과 대칭)" begin
        mc(v) = ask("""{"kind":"montecarlo","seed":1,"iterations":100,"horizon_months":6,"initial_balance_minor":"$v","monthly_net_minor_history":["1","2","3","4","5","6"]}""")
        # 2^53 = 9007199254740992 — 초과는 Float64 에서 조용히 잘리므로 거절
        @test mc("9007199254740993").ok === false
        @test mc("-9007199254740993").ok === false
        @test mc("9007199254740992").ok === true      # 정확 표현 가능한 경계는 수용
        # history 원소도 같은 가드를 받는다
        @test ask("""{"kind":"montecarlo","seed":1,"iterations":100,"horizon_months":6,"initial_balance_minor":"0","monthly_net_minor_history":["1","2","3","4","5","9007199254740993"]}""").ok === false
        # repayment 는 Int128 정수 산술이라 계약 상한(18자리)을 그대로 받는다
        @test ask("""{"kind":"repayment","budget_minor":"999999999999999999","debts":[{"id":"big","balance_minor":"999999999999999999","rate_num":0,"rate_den":1,"min_payment_minor":"999999999999999999"}]}""").ok === true
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

    HIST = """["120000","-80000","150000","-40000","90000","-60000","200000","-110000","70000","-30000","130000","-50000"]"""

    @testset "T9 scenario — 가정별 비교 (공통 난수)" begin
        req = """{"kind":"scenario","seed":424242,"iterations":4000,"horizon_months":18,"initial_balance_minor":"2000000","monthly_net_minor_history":$HIST,"scenarios":[{"label":"opt","net_mult_num":11,"net_mult_den":10,"net_delta_minor":"60000"},{"label":"base"},{"label":"pess","net_mult_num":9,"net_mult_den":10,"net_delta_minor":"-120000"}]}"""
        r = ask(req)
        @test r.ok === true
        @test length(r.scenarios) == 3
        @test [s.label for s in r.scenarios] == ["opt", "base", "pess"]
        for s in r.scenarios
            # 확률·CI 는 고정 자릿수 문자열 (Float 직렬화 편차 차단)
            @test occursin(r"^[01]\.[0-9]{4}$", s.depletion_probability)
            @test occursin(r"^[01]\.[0-9]{6}$", s.ci95_halfwidth)
            qs = [s.final_balance_quantiles[k] for k in (:p05, :p25, :p50, :p75, :p95)]
            @test all(q -> occursin(r"^-?[0-9]+$", q), qs)
            @test issorted(parse.(Int64, qs))                # 분위수 단조 비감소
            # runway 는 null(소진 0건) 또는 1..horizon 정수 문자열
            @test s.median_runway_months === nothing ||
                  (occursin(r"^[0-9]+$", s.median_runway_months) &&
                   1 <= parse(Int, s.median_runway_months) <= 18)
        end
        p50s = [parse(Int64, s.final_balance_quantiles.p50) for s in r.scenarios]
        dps  = [parse(Float64, s.depletion_probability) for s in r.scenarios]
        # 낙관 > 기준 > 비관 (기말잔액 중앙값), 소진확률은 역방향 단조 비감소
        @test p50s[1] > p50s[2] > p50s[3]
        @test dps[1] <= dps[2] <= dps[3]
        # 결정론: 재실행 완전 동일
        @test ask(req).scenarios[3].final_balance_quantiles.p50 ==
              r.scenarios[3].final_balance_quantiles.p50
        # 항등 조정(base = 배수 1/1·delta 0)은 같은 파라미터 montecarlo 와 바이트 일치해야 한다
        # — scenario 가 montecarlo 핵심(simulate_paths)을 그대로 재사용함을 못박는다.
        mc = ask("""{"kind":"montecarlo","seed":424242,"iterations":4000,"horizon_months":18,"initial_balance_minor":"2000000","monthly_net_minor_history":$HIST}""")
        base = r.scenarios[2]
        @test base.depletion_probability == mc.depletion_probability
        @test base.ci95_halfwidth == mc.ci95_halfwidth
        for k in (:p05, :p25, :p50, :p75, :p95)
            @test base.final_balance_quantiles[k] == mc.final_balance_quantiles[k]
        end
    end

    @testset "T10 sensitivity — 파라미터 격자 + threshold" begin
        req = """{"kind":"sensitivity","seed":20260722,"iterations":3000,"horizon_months":12,"initial_balance_minor":"500000","monthly_net_minor_history":$HIST,"sweep":{"param":"monthly_net_delta_minor","start_minor":"-120000","stop_minor":"120000","steps":5},"target_probability":"0.1000"}"""
        r = ask(req)
        @test r.ok === true
        @test r.param == "monthly_net_delta_minor"
        @test length(r.grid) == 5
        vals = [parse(Int64, g.value_minor) for g in r.grid]
        # 격자 양 끝점 정확, 등간격, 홀수 steps 중앙은 정확히 0
        @test vals[1] == -120000
        @test vals[end] == 120000
        @test vals[3] == 0
        @test all(diff(vals) .== 60000)                      # 240000/4
        dps  = [parse(Float64, g.depletion_probability) for g in r.grid]
        p50s = [parse(Int64, g.final_balance_p50_minor) for g in r.grid]
        # 공통 난수: delta↑ → 소진확률 단조 비증가, 중앙 기말잔액 단조 비감소
        @test issorted(dps; rev = true)
        @test issorted(p50s)
        # 정확 선형: 인접 격자 p50 차이 = horizon × delta_step (floor(x+정수)=floor(x)+정수).
        # 대역폭이 위치 이동 불변이고 공통 난수라서 정확히 성립한다.
        @test all(diff(p50s) .== 12 * 60000)
        # 중앙 격자(delta=0)는 같은 파라미터 montecarlo 와 바이트 일치
        mc = ask("""{"kind":"montecarlo","seed":20260722,"iterations":3000,"horizon_months":12,"initial_balance_minor":"500000","monthly_net_minor_history":$HIST}""")
        @test r.grid[3].final_balance_p50_minor == mc.final_balance_quantiles.p50
        @test r.grid[3].depletion_probability == mc.depletion_probability
        # threshold: 표시 소진확률이 목표(0.1000) 이하로 처음 떨어지는 격자 값
        @test r.threshold_value_minor !== nothing
        ti = findfirst(==(parse(Int64, r.threshold_value_minor)), vals)
        @test dps[ti] <= 0.1000
        @test ti == 1 || dps[ti - 1] > 0.1000                # 바로 앞 격자는 목표 초과
        # target 미지정 → threshold null
        r2 = ask("""{"kind":"sensitivity","seed":20260722,"iterations":3000,"horizon_months":12,"initial_balance_minor":"500000","monthly_net_minor_history":$HIST,"sweep":{"param":"monthly_net_delta_minor","start_minor":"-120000","stop_minor":"120000","steps":5}}""")
        @test r2.threshold_value_minor === nothing
    end

    @testset "T11 scenario·sensitivity 오류 계약" begin
        h = """["1","2","3","4","5","6"]"""
        scen(body) = ask("""{"kind":"scenario","seed":1,"iterations":50,"horizon_months":6,"initial_balance_minor":"0","monthly_net_minor_history":$h,"scenarios":$body}""")
        sens(tail) = ask("""{"kind":"sensitivity","seed":1,"iterations":50,"horizon_months":6,"initial_balance_minor":"0","monthly_net_minor_history":$h,"sweep":$tail}""")
        # scenario: 라벨 중복 / 라벨 누락 / 9개(>8) / net_mult_den 0
        @test scen("""[{"label":"a"},{"label":"a"}]""").ok === false
        @test scen("""[{"net_delta_minor":"0"}]""").ok === false
        nine = join(["""{"label":"s$i"}""" for i in 1:9], ",")
        @test scen("[$nine]").ok === false
        @test scen("""[{"label":"a","net_mult_den":0}]""").ok === false
        # scenario: seed 누락(결정론 필수)
        @test ask("""{"kind":"scenario","iterations":50,"horizon_months":6,"initial_balance_minor":"0","monthly_net_minor_history":$h,"scenarios":[{"label":"a"}]}""").ok === false
        # scenario: 조정 결과가 2^53 초과 → 거절 (통계 경로 정밀도 가드)
        @test ask("""{"kind":"scenario","seed":1,"iterations":50,"horizon_months":6,"initial_balance_minor":"0","monthly_net_minor_history":["9007199254740000","1","2","3","4","5"],"scenarios":[{"label":"a","net_delta_minor":"1000000"}]}""").ok === false
        # sensitivity: 미지원 param / start>=stop / steps<2
        @test sens("""{"param":"interest","start_minor":"0","stop_minor":"100","steps":3}""").ok === false
        @test sens("""{"param":"monthly_net_delta_minor","start_minor":"100","stop_minor":"100","steps":3}""").ok === false
        @test sens("""{"param":"monthly_net_delta_minor","start_minor":"-100","stop_minor":"100","steps":1}""").ok === false
        # sensitivity: target_probability 형식 오류(고정 4자리 문자열 아님)
        @test ask("""{"kind":"sensitivity","seed":1,"iterations":50,"horizon_months":6,"initial_balance_minor":"0","monthly_net_minor_history":$h,"sweep":{"param":"monthly_net_delta_minor","start_minor":"-100","stop_minor":"100","steps":3},"target_probability":"0.5"}""").ok === false
    end
end
