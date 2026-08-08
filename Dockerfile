ARG GLEAM_VERSION=v1.18.1
ARG ERLANG_VERSION=29.0.4

# Build Caddy
FROM caddy:2-builder-alpine AS caddy-builder
RUN xcaddy build \
    --with github.com/mholt/caddy-ratelimit

# Build Gleam
FROM ghcr.io/gleam-lang/gleam:${GLEAM_VERSION}-erlang-alpine AS gleam-bin

# Use Erlang runtime to have git available for git dependencies
FROM erlang:${ERLANG_VERSION} AS builder
COPY --from=gleam-bin /bin/gleam /bin/gleam

COPY ./shared /build/shared
COPY ./client /build/client
COPY ./server /build/server

RUN cd /build/shared && gleam deps download
RUN cd /build/client && gleam deps download
RUN cd /build/server && gleam deps download

RUN cd /build/client \
    && gleam run -m lustre/dev build --minify --outdir=../server/priv/static/
RUN cd /build/server \
    && gleam export erlang-shipment

# Run
FROM ghcr.io/gleam-lang/gleam:${GLEAM_VERSION}-erlang-alpine

COPY --from=caddy-builder /usr/bin/caddy /usr/bin/caddy
COPY --from=builder /build/server/build/erlang-shipment /app

WORKDIR /app
RUN chmod +x /app/entrypoint.sh

COPY Caddyfile /etc/caddy/Caddyfile
COPY start.sh /start.sh
RUN chmod +x /start.sh

ENV CADDY_PORT=8080
ENV PORT=4000
CMD ["/start.sh"]
