ExUnit.start()

# DB 통합 테스트는 DATABASE_URL 이 있을 때만 돈다.
# 없으면 순수 로직(봉투 파싱·라우팅·임계 판정·채널 격리)만 검증한다.
if System.get_env("DATABASE_URL") in [nil, ""] do
  ExUnit.configure(exclude: [:db])
end
