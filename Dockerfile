ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28
ARG DEBIAN_SLIM=bookworm-slim
ARG MIX_ENV=prod

FROM docker.io/elixir:${ELIXIR_VERSION}-otp-${OTP_VERSION} AS build

ARG MIX_ENV

ENV MIX_ENV=${MIX_ENV} \
  HEX_MIX_ARCHIVES=https://repo.hex.pm/archive

WORKDIR /app

RUN apt-get update -y && \
  apt-get install -y build-essential git nodejs npm && \
  rm -rf /var/lib/apt/lists/*

RUN mix local.hex --force && \
  mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only ${MIX_ENV}
RUN mix deps.compile

# Compile first so phoenix-colocated hooks are extracted from LiveViews
COPY config/config.exs config/${MIX_ENV}.exs config/runtime.exs ./config/
COPY lib ./lib
COPY priv ./priv
RUN mix compile

# Install and build JS assets (depends on phoenix-colocated from compilation above)
COPY assets/package.json assets/package-lock.json* assets/
RUN cd assets && npm ci
COPY assets ./assets

RUN mix assets.deploy
RUN mix release

FROM docker.io/debian:${DEBIAN_SLIM} AS app

ARG MIX_ENV

RUN apt-get update -y && \
  apt-get install -y libodbc1 libsasl2-modules ca-certificates && \
  rm -rf /var/lib/apt/lists/*

RUN groupadd -g 1000 elixir && \
  useradd -u 1000 -g elixir -m elixir

WORKDIR /app

COPY --from=build --chown=elixir:elixir /app/_build/${MIX_ENV}/rel/pantheon ./

USER elixir

EXPOSE 4000

ENV LANG=C.UTF-8

CMD ["bin/pantheon", "start"]
