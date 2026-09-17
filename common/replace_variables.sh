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

# /opt/hiddify-manager/.venv313/bin/python -c "import json5;import jinja2" || uv pip install json5 jinja2
# rm -f /opt/hiddify-manager/singbox/configs/*.json
rm -f /opt/hiddify-manager/xray/configs/05_inbounds_10*.json*
rm -f /opt/hiddify-manager/xray/configs/05_inbounds_h2*.json*
rm -f /opt/hiddify-manager/xray/configs/05_inbounds_02_realitygrpc*.json*
rm -f /opt/hiddify-manager/xray/configs/05_inbounds_02_realityh2*.json*
rm -f /opt/hiddify-manager/singbox/configs/05_inbounds_2071_realitygrpc_main.json*
rm -f /opt/hiddify-manager/singbox/configs/05_inbounds_20[123][1234]*.json*


/opt/hiddify-manager/common/jinja.py $MODE
