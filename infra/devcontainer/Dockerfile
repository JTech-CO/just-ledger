# just-ledger 개발·CI 공용 이미지
# 11개 툴체인을 한 이미지에 담는다. 배포용 슬림 이미지는 infra/deploy/ 에 별도로 둔다.
# 레이어는 변경 빈도가 낮은 것부터 배치했다. 버전 ARG는 PROGRESS.md 툴체인 표와 동기화한다.

# ---------------------------------------------------------------------------
# Elixir/Erlang은 공식 이미지에서 복사한다. Ubuntu 배포판 패키지는 버전이 낡고,
# Erlang Solutions 저장소는 배포판별 경로가 자주 바뀐다.
# ---------------------------------------------------------------------------
# 태그는 Docker Hub 실존 확인됨 (2026-07-21). 베이스(ubuntu:24.04=noble)와 glibc 호환 필수.
ARG ELIXIR_IMAGE=hexpm/elixir:1.18.3-erlang-27.3.3-ubuntu-noble-20260509.1
FROM ${ELIXIR_IMAGE} AS elixir-src

# ---------------------------------------------------------------------------
FROM ubuntu:24.04 AS dev

ARG NODE_VERSION=24.16.0
ARG GO_VERSION=1.26.5
ARG JULIA_VERSION=1.11.5
ARG GNUCOBOL_VERSION=3.2

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=ko_KR.UTF-8 \
    LC_ALL=ko_KR.UTF-8 \
    PATH=/usr/local/go/bin:/usr/local/node/bin:/usr/local/julia/bin:/root/.cargo/bin:/root/.ghcup/bin:$PATH

# --- 1. 기반 패키지 + 로케일 -------------------------------------------------
# ko_KR 로케일은 CP949 인코딩 명세서 처리 테스트에 필요하다.
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential curl wget git ca-certificates gnupg pkg-config \
      xz-utils unzip zip file locales tzdata jq \
      libssl-dev libncurses-dev libreadline-dev zlib1g-dev \
      libgmp-dev libdb-dev libxml2-dev libjson-c-dev gettext \
      cmake libicu-dev ruby ruby-dev \
 && sed -i 's/^# *\(ko_KR.UTF-8\)/\1/; s/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen \
 && locale-gen \
 && rm -rf /var/lib/apt/lists/*

# --- 2. Node.js (메인 언어) --------------------------------------------------
RUN curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
      | tar -xJ -C /usr/local \
 && mv "/usr/local/node-v${NODE_VERSION}-linux-x64" /usr/local/node \
 && npm install -g pnpm

# --- 3. Go -------------------------------------------------------------------
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
      | tar -xz -C /usr/local

# --- 4. Rust + wasm 타깃 -----------------------------------------------------
# 실제 버전은 레포 루트 rust-toolchain.toml 로 고정한다.
RUN curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable \
 && rustup target add wasm32-unknown-unknown \
 && cargo install wasm-pack --locked

# --- 5. Haskell (GHC + cabal) ------------------------------------------------
ENV BOOTSTRAP_HASKELL_NONINTERACTIVE=1 \
    BOOTSTRAP_HASKELL_MINIMAL=0
RUN curl -fsSL https://get-ghcup.haskell.org | sh \
 && ghcup install ghc --set recommended \
 && ghcup install cabal --set latest \
 && cabal update

# --- 6. GnuCOBOL (소스 빌드) --------------------------------------------------
# 배포판 패키지는 버전이 낡고 COMP-3 바이트 표현 재현성을 보장하기 어렵다.
RUN curl -fsSL "https://ftp.gnu.org/gnu/gnucobol/gnucobol-${GNUCOBOL_VERSION}.tar.xz" -o /tmp/gc.tar.xz \
 && tar -xJf /tmp/gc.tar.xz -C /tmp \
 && cd "/tmp/gnucobol-${GNUCOBOL_VERSION}" \
 && ./configure --prefix=/usr/local \
 && make -j"$(nproc)" && make install && ldconfig \
 && rm -rf /tmp/gnucobol-* /tmp/gc.tar.xz

# --- 7. SWI-Prolog -----------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      software-properties-common \
 && add-apt-repository -y ppa:swi-prolog/stable \
 && apt-get update && apt-get install -y --no-install-recommends swi-prolog-nox \
 && rm -rf /var/lib/apt/lists/*

# --- 8. R + 분석 패키지 -------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      r-base r-base-dev libcurl4-openssl-dev libfontconfig1-dev \
      libharfbuzz-dev libfribidi-dev libfreetype6-dev libpng-dev libtiff5-dev libjpeg-dev \
 && Rscript -e 'install.packages(c("ggplot2","jsonlite","svglite"), repos="https://cloud.r-project.org")' \
 && rm -rf /var/lib/apt/lists/*

# --- 9. Julia ----------------------------------------------------------------
RUN curl -fsSL "https://julialang-s3.julialang.org/bin/linux/x64/${JULIA_VERSION%.*}/julia-${JULIA_VERSION}-linux-x86_64.tar.gz" \
      | tar -xz -C /usr/local \
 && mv "/usr/local/julia-${JULIA_VERSION}" /usr/local/julia \
 && julia -e 'using Pkg; Pkg.add(["Distributions","StatsBase","JSON3"]); Pkg.precompile()'

# --- 10. Elixir / Erlang (공식 이미지에서 복사) --------------------------------
COPY --from=elixir-src /usr/local/lib/erlang /usr/local/lib/erlang
COPY --from=elixir-src /usr/local/lib/elixir /usr/local/lib/elixir
RUN ln -sf /usr/local/lib/erlang/bin/* /usr/local/bin/ \
 && ln -sf /usr/local/lib/elixir/bin/* /usr/local/bin/ \
 && mix local.hex --force && mix local.rebar --force

# --- 11. Lua + LuaRocks ------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      lua5.4 liblua5.4-dev luarocks \
 && luarocks --lua-version=5.4 install dkjson \
 && lua5.4 -e 'require("dkjson")' \
 && rm -rf /var/lib/apt/lists/*

# --- 12. PostgreSQL 클라이언트 ------------------------------------------------
RUN install -d /usr/share/postgresql-common/pgdg \
 && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
 && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] \
      https://apt.postgresql.org/pub/repos/apt noble-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list \
 && apt-get update && apt-get install -y --no-install-recommends postgresql-client-18 \
 && rm -rf /var/lib/apt/lists/*

# --- 13. github-linguist (언어 구성 계측) -------------------------------------
RUN gem install github-linguist --no-document

WORKDIR /workspace
CMD ["bash"]
