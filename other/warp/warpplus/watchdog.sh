#!/bin/bash
# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
# watashi v12.3.33dev: warp watchdog
#
# Runs beside warp-plus (started by engine-start.sh).
# Three jobs in one loop:
#
#   1. HEALTHCHECK  — every WS_WD_INTERVAL seconds it sends real traffic
#      through the SOCKS5 proxy. If the proxy carries the traffic, the
#      node is healthy. If it doesn't, the failure counter goes up.
#
#   2. AUTO-ROTATION — when the failure counter reaches WS_WD_THRESHOLD
#      it deletes the pinned endpoint so the next start uses --scan to
#      find a fresh one, then kills warp-plus. systemd (Restart=always)
#      brings it back through engine-start.sh which starts a new watchdog.
#
#   3. KEEPALIVE (connection pooling substitute) — on every healthy tick
#      it also sends a tiny ping that keeps the WireGuard handshake warm
#      so idle connections are never dropped mid-session. This avoids the
#      "first packet after silence is always lost" problem that looks like
#      random latency spikes.
#
# Usage: called by engine-start.sh
#   watchdog.sh <warp_plus_pid>

WARP_PID="${1:-0}"
DIR="/opt/watashi-manager/other/warp/warpplus"
CACHE="$DIR/cache"
PIN="$CACHE/.watashi-endpoint"
PROXY="socks5h://127.0.0.1:3000"

# ── tunables (can be overridden in engine.conf) ──────────────────────────────
WS_WD_INTERVAL="${WS_WD_INTERVAL:-300}"      # seconds between checks (default 5 min)
WS_WD_THRESHOLD="${WS_WD_THRESHOLD:-2}"       # failures before rotating
WS_WD_GRACE="${WS_WD_GRACE:-60}"              # wait for tunnel to come up at start
WS_WD_TEST_URL="${WS_WD_TEST_URL:-http://cp.cloudflare.com/}"   # healthcheck target
WS_WD_KEEPALIVE_URL="${WS_WD_KEEPALIVE_URL:-http://1.1.1.1}"   # keepalive target
# ─────────────────────────────────────────────────────────────────────────────

fail_count=0

log()  { echo "[warp-watchdog] $*" >&2; }
warn() { echo -e "\033[93m[warp-watchdog] $*\033[0m" >&2; }
ok()   { echo -e "\033[92m[warp-watchdog] $*\033[0m" >&2; }

# source engine.conf so WS_WD_* overrides inside it are respected
[ -f "$DIR/engine.conf" ] && source "$DIR/engine.conf" 2>/dev/null

log "started (PID $$, watching warp-plus PID $WARP_PID)"
log "interval=${WS_WD_INTERVAL}s  threshold=${WS_WD_THRESHOLD}  grace=${WS_WD_GRACE}s"

# ── grace period: let the tunnel come up before the first check ───────────────
sleep "$WS_WD_GRACE"

# ── main loop ────────────────────────────────────────────────────────────────
while true; do

    # Exit when warp-plus dies (engine-start.sh already exits too, but be tidy)
    if [ "$WARP_PID" -gt 0 ] && ! kill -0 "$WARP_PID" 2>/dev/null; then
        log "warp-plus (PID $WARP_PID) exited — watchdog stopping."
        exit 0
    fi

    # ── healthcheck ──────────────────────────────────────────────────────────
    http_code=$(curl \
        --socks5-hostname "${PROXY#socks5h://}" \
        --max-time 12 \
        --silent \
        --output /dev/null \
        --write-out "%{http_code}" \
        "$WS_WD_TEST_URL" 2>/dev/null)

    if echo "$http_code" | grep -qE '^(200|204|301|302)$'; then
        # ── healthy ─────────────────────────────────────────────────────────
        ok "connection OK (http $http_code) — next check in ${WS_WD_INTERVAL}s"
        fail_count=0

        # ── keepalive ping (keeps WireGuard handshake warm) ─────────────────
        # A tiny HEAD request uses almost no bandwidth but prevents the
        # WireGuard session from going idle, which is the root cause of the
        # "first packet is always slow" problem.
        curl \
            --socks5-hostname "${PROXY#socks5h://}" \
            --max-time 5 \
            --silent \
            --head \
            --output /dev/null \
            "$WS_WD_KEEPALIVE_URL" 2>/dev/null || true

    else
        # ── unhealthy ───────────────────────────────────────────────────────
        fail_count=$((fail_count + 1))
        warn "connection check FAILED (code='$http_code', failure $fail_count/$WS_WD_THRESHOLD)"

        if [ "$fail_count" -ge "$WS_WD_THRESHOLD" ]; then
            warn "threshold reached — clearing pinned endpoint and rotating."
            rm -f "$PIN"
            fail_count=0

            # Fix: also update engine.args so the next systemd restart does NOT
            # reuse the dead endpoint that was hardcoded in it. We strip
            # --endpoint + its address and, if SCAN=1 in engine.conf, add
            # --scan so warp-plus can find a fresh working endpoint by itself.
            ARGS_FILE="$DIR/engine.args"
            if [ -f "$ARGS_FILE" ]; then
                awk '/^--endpoint$/{skip=1;next} skip{skip=0;next} {print}'                     "$ARGS_FILE" > "${ARGS_FILE}.tmp"
                if grep -q '^SCAN=1' "$DIR/engine.conf" 2>/dev/null; then
                    echo "--scan" >> "${ARGS_FILE}.tmp"
                fi
                mv "${ARGS_FILE}.tmp" "$ARGS_FILE"
                log "engine.args updated (endpoint removed$(grep -q --scan $ARGS_FILE 2>/dev/null && echo ', --scan added' || echo ''))."
            fi

            # Kill warp-plus; systemd Restart=always brings engine-start.sh
            # back with the updated engine.args.
            if [ "$WARP_PID" -gt 0 ]; then
                kill -TERM "$WARP_PID" 2>/dev/null
            fi
            log "rotation signal sent — watchdog exiting."
            exit 0
        fi
    fi

    sleep "$WS_WD_INTERVAL"
done
