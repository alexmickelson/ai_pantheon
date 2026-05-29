ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28
ARG ALPINE_VERSION=3.23
ARG MIX_ENV=prod

# Build stage: Alpine for musl-compatible release
FROM docker.io/elixir:${ELIXIR_VERSION}-otp-${OTP_VERSION}-alpine AS build

ARG MIX_ENV

ENV MIX_ENV=${MIX_ENV} \
  HEX_MIX_ARCHIVES=https://repo.hex.pm/archive

WORKDIR /app

RUN apk add --no-cache gcc musl-dev git nodejs npm

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

FROM docker.io/library/alpine:${ALPINE_VERSION} AS app

ARG MIX_ENV

RUN apk add --no-cache libgcc libstdc++ ncurses libsasl ca-certificates openssl

RUN addgroup -g 1000 elixir && \
  adduser -u 1000 -G elixir -D elixir

WORKDIR /app

COPY --from=build --chown=elixir:elixir /app/_build/${MIX_ENV}/rel/pantheon ./

USER elixir

EXPOSE 4000

ENV LANG=C.UTF-8

CMD ["bin/pantheon", "start"]
