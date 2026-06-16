# Find eligible builder and runner images on Docker Hub.
# https://hub.docker.com/r/hexpm/elixir/tags
# https://hub.docker.com/_/debian?tab=tags&page=1&name=bookworm-slim
#
# Adjust these ARGs to match your local versions:
#   elixir --version
#   node --version
ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.3.1
ARG DEBIAN_VERSION=trixie-20260202-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# install Node.js (needed for PostCSS/Tailwind CSS build)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# install the Rust toolchain — Rustler compiles the chess-engine NIF
# (native/chess_nif) during `mix compile`.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --default-toolchain stable --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# copy npm package files and design tokens for assets.setup (npm install + sugarcube generate)
COPY assets/package.json assets/package-lock.json assets/
COPY assets/design-tokens assets/design-tokens

RUN mix assets.setup

COPY priv priv

COPY lib lib

# Rust sources for the chess NIF — must be present before `mix compile`, which
# triggers Rustler to build native/chess_nif (and its vendored native/chess_core).
COPY native native

# Compile the release (also builds the Rust NIF)
RUN mix compile

COPY assets assets

# compile assets
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

# `stockfish` powers the contact-gate puzzle's bot defense; libstdc++6 is needed
# by the compiled Rust NIF. (Without stockfish the app falls back to the core
# engine, but we ship it so the bot defends well.)
RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates stockfish \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/braidonwhatley ./

USER nobody

CMD ["/app/bin/server"]
