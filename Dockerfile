# Build Caddy
FROM caddy:2-builder-alpine AS caddy-builder
RUN xcaddy build \
    --with github.com/mholt/caddy-ratelimit

# Build Gleam
FROM erlang:29.0.4 AS build
COPY --from=ghcr.io/gleam-lang/gleam:v1.18.1-erlang-alpine /bin/gleam /bin/gleam
COPY . /app/
RUN cd /app/client && gleam run -m lustre/dev build --outdir=/app/server/priv/static/ --minify
RUN cd /app/server && gleam export erlang-shipment

# Run
FROM erlang:29.0.1-alpine
COPY --from=caddy-builder /usr/bin/caddy /usr/bin/caddy

COPY --from=build /app/server/build/erlang-shipment /app
WORKDIR /app
RUN chmod +x /app/entrypoint.sh

COPY Caddyfile /etc/caddy/Caddyfile
COPY start.sh /start.sh
RUN chmod +x /start.sh

ENV CADDY_PORT=8080
ENV PORT=4000
CMD ["/start.sh"]
