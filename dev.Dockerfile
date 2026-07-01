FROM docker.io/elixir:1.19.5-otp-28-alpine AS build

RUN apk add --no-cache build-base git bash nodejs npm inotify-tools postgresql-dev

WORKDIR /app

ENV USER="elixir"
ENV HEX_MIX_ARCHIVES=https://repo.hex.pm/archive

RUN addgroup -g 1000 $USER && \
    adduser -D -u 1000 -G $USER $USER

RUN mkdir -p /app/_build && \
    chown -R elixir:elixir /app

USER elixir

RUN mix local.hex --force && \
    mix local.rebar --force

COPY --chown=elixir:elixir mix.exs mix.lock ./
RUN mix deps.get

COPY --chown=elixir:elixir assets assets/

EXPOSE 4000

CMD ["mix", "phx.server"]
