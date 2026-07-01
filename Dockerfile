FROM docker.io/elixir:1.19.5-otp-28-alpine AS build


ENV MIX_ENV=prod \
  HEX_MIX_ARCHIVES=https://repo.hex.pm/archive

WORKDIR /app

RUN apk add --no-cache gcc musl-dev git nodejs npm

RUN mix local.hex --force && \
  mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Compile first so phoenix-colocated hooks are extracted from LiveViews
COPY config/config.exs config/prod.exs config/runtime.exs ./config/
COPY lib ./lib
COPY priv ./priv
RUN mix compile

COPY assets/package.json assets/package-lock.json* assets/
RUN cd assets && npm ci
COPY assets ./assets

RUN mix assets.deploy
RUN mix release

FROM docker.io/library/alpine:3.23 AS app

ARG MIX_ENV

RUN apk add --no-cache libgcc libstdc++ ncurses libsasl ca-certificates openssl

RUN addgroup -g 1000 elixir && \
  adduser -u 1000 -G elixir -D elixir

WORKDIR /app

COPY --from=build --chown=elixir:elixir /app/_build/prod/rel/pantheon ./

USER elixir

EXPOSE 4000

ENV LANG=C.UTF-8

CMD ["bin/pantheon", "start"]
