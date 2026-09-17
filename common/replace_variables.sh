cd $(dirname -- "$0")
source ./utils.sh
activate_python_venv

domains=$(cat ../current.json | jq -r '.domains[] | .domain' | tr '\n' ' ')


# watashi v12.2.130: this sweep decides what to delete from the list of domains it
# just read out of current.json. When that read fails, or the panel has no
# domain yet, the list is empty and the sweep used to delete every
# certificate on the machine, after which haproxy could not start at all.
# An empty list is now treated as no answer rather than as no domains.
if [[ -z "${domains// /}" ]]; then
    echo "watashi: no domain was read from current.json, so the ssl folder is left alone"
else
    shopt -s nullglob  # Prevent errors when no files match
    for f in /opt/hiddify-manager/ssl/*.crt; do
        d=$(basename "$f" .crt)
        if [[ ! " ${domains[@]} " =~ " ${d} " ]]; then
            rm -f "/opt/hiddify-manager/ssl/$d.crt" 2>/dev/null || true
            rm -f "/opt/hiddify-manager/ssl/$d.crt.key" 2>/dev/null || true
        fi
    done
    shopt -u nullglob
fi

# we need at least one ssl certificate to be able to run haproxy
for d in $domains; do
    (bash /opt/hiddify-manager/acme.sh/generate_self_signed_cert.sh $d >/dev/null 2>&1)
done

# watashi v12.2.130h: the renderer needs these two. A fresh install once reached
# this line without json5 and rendered nothing at all, so the check is real
# now instead of commented out.
ws_ensure_render_deps() {
    local py=/opt/hiddify-manager/.venv313/bin/python
    [ -x "$py" ] || return 0
    "$py" -c "import json5, jinja2" >/dev/null 2>&1 && return 0
    echo "watashi: the render packages are missing, installing them"
    if command -v uv >/dev/null 2>&1; then
        uv pip install --python "$py" json5 jinja2 >/dev/null 2>&1 \
            || VIRTUAL_ENV=/opt/hiddify-manager/.venv313 uv pip install json5 jinja2 >/dev/null 2>&1
    fi
    "$py" -c "import json5, jinja2" >/dev/null 2>&1 && return 0
    "$py" -m pip install json5 jinja2 >/dev/null 2>&1 || true
    "$py" -c "import json5, jinja2" >/dev/null 2>&1 \
        || echo "watashi: json5 could not be installed, the renderer will use plain json"
}
ws_ensure_render_deps
# rm -f /opt/hiddify-manager/singbox/configs/*.json
rm -f /opt/hiddify-manager/xray/configs/05_inbounds_10*.json*
rm -f /opt/hiddify-manager/xray/configs/05_inbounds_h2*.json*
rm -f /opt/hiddify-manager/xray/configs/05_inbounds_02_realitygrpc*.json*
rm -f /opt/hiddify-manager/xray/configs/05_inbounds_02_realityh2*.json*
rm -f /opt/hiddify-manager/singbox/configs/05_inbounds_2071_realitygrpc_main.json*
rm -f /opt/hiddify-manager/singbox/configs/05_inbounds_20[123][1234]*.json*


/opt/hiddify-manager/common/jinja.py $MODE
