#!/bin/sh
PORT=$PORT /app/entrypoint.sh run &

sleep 2

caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
