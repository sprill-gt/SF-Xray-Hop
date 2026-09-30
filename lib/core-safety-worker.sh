#!/usr/bin/env bash
# Invoked ONLY inside the private-network DynamicUser unit in core.sh. Uses
# generated VLESS identities, no production credentials, DNS or Internet access.
set -euo pipefail
umask 077
export LC_ALL=C
[[ $# == 2 ]] || exit 2
binary=$1; targets=$2; pid=''
work=$(mktemp -d /tmp/sfxh-core-safety.XXXXXXXX)
cleanup() {
    if [[ -n $pid ]]; then kill "$pid" 2>/dev/null || :; wait "$pid" 2>/dev/null || :; fi
    rm -rf -- "$work"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP
direct=$("$binary" uuid); relay=$("$binary" uuid)
jq -n --arg direct "$direct" --arg relay "$relay" '
  def local_http($tag;$port): {tag:$tag,listen:"127.0.0.1",port:$port,protocol:"http"};
  def client($tag;$id): {tag:$tag,protocol:"vless",settings:{address:"127.0.0.1",port:19501,id:$id,encryption:"none"}};
  {log:{loglevel:"info"},
   inbounds:[{tag:"guard-vless",listen:"127.0.0.1",port:19501,protocol:"vless",settings:{decryption:"none",
     clients:[{id:$direct,email:"sf-xray-hop-direct"},{id:$relay,email:"sf-xray-hop-relay"}]}},
     local_http("guard-direct";19502),local_http("guard-relay";19503),
     {tag:"guard-receiver",listen:"::",port:19504,protocol:"dokodemo-door",settings:{address:"127.0.0.1",port:9,network:"tcp"}}],
   outbounds:[{tag:"reject",protocol:"blackhole"},
     {tag:"response",protocol:"blackhole",settings:{response:{type:"http"}}},
     {tag:"guard-freedom",protocol:"freedom"},client("client-direct";$direct),client("client-relay";$relay)],
   routing:{domainStrategy:"AsIs",rules:[
     {type:"field",inboundTag:["guard-receiver"],outboundTag:"response"},
     {type:"field",inboundTag:["guard-direct"],outboundTag:"client-direct"},
     {type:"field",inboundTag:["guard-relay"],outboundTag:"client-relay"},
     {type:"field",inboundTag:["guard-vless"],domain:["full:control.sfxh.test"],outboundTag:"response"},
     {type:"field",inboundTag:["guard-vless"],user:["sf-xray-hop-direct","sf-xray-hop-relay"],outboundTag:"guard-freedom"}]}}
' > "$work/config.json"
"$binary" run -config "$work/config.json" > "$work/core.log" 2>&1 &
pid=$!
ready=0
for attempt in {1..60}; do
    kill -0 "$pid" 2>/dev/null || { printf 'candidate-core-start-failed\n' >&2; exit 1; }
    if (exec 3<>/dev/tcp/127.0.0.1/19502) 2>/dev/null; then ready=1; break; fi
    sleep 0.1
done
((ready)) || exit 1
# The receiver must be reachable without VLESS, on BOTH address families.
for host in 127.0.0.1 '[::1]'; do
    status=$(curl --silent --proxy '' --noproxy '*' --connect-timeout 1 --max-time 3 -o /dev/null -w '%{http_code}' "http://$host:19504/")
    [[ $status == 403 ]] || { printf 'receiver-control-failed\n' >&2; exit 1; }
done
checks=0
for proxy in 19502 19503; do
    # Positive authenticated control distinguishes broken authentication from
    # blocked targets; public freedom/HTTPS is separately tested by the caller.
    status=$(curl --silent --proxy "http://127.0.0.1:$proxy" --noproxy '' --connect-timeout 1 --max-time 3 -o /dev/null -w '%{http_code}' http://control.sfxh.test/)
    [[ $status == 403 ]] || { printf 'authenticated-control-failed\n' >&2; exit 1; }
    while IFS=$'\t' read -r name host ip; do
        log_host=$ip; [[ $ip != *:* ]] || log_host="[$ip]"
        pattern="blocked target: tcp:$log_host:19504"
        before=$(grep -Fc "$pattern" "$work/core.log" || :)
        status=$(curl --silent --proxy "http://127.0.0.1:$proxy" --noproxy '' --connect-timeout 1 --max-time 1.5 -o /dev/null -w '%{http_code}' "http://$host:19504/" 2>/dev/null) || :
        after=$(grep -Fc "$pattern" "$work/core.log" || :)
        # A timeout alone is NEVER positive evidence of protection. Require the
        # candidate core to report a new final-outbound block for this target.
        if [[ $status != 000 ]] || ((after<=before)); then
            printf 'private-target-protection-unconfirmed: %s profile=%s\n' "$name" "$proxy" >&2
            exit 1
        fi
        ((checks+=1))
    done < <(jq -r '.targets[]|[.name,.host,.ip]|@tsv' "$targets")
done
kill -0 "$pid"
jq -n --argjson checks "$checks" '{status:"pass",tcpChecks:$checks,identities:2,receiverControls:2,authenticatedControls:2,
  scope:"isolated VLESS-to-freedom TCP private-address canaries; not a full core security audit"}'
