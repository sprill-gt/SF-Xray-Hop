#!/usr/bin/env bash
set -euo pipefail
SFXH_CODE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export SFXH_TEST_MODE=1 SFXH_TEST_ROOT=$SFXH_CODE/.cache/reporting-root
source "$SFXH_CODE/lib/common.sh"
source "$SFXH_CODE/lib/benchmark.sh"
sf_paths; sf_dirs
work=$(sf_temp)
trap 'sf_remove_tree "$work"' EXIT
classify() { jq -L "$SFXH_CODE/templates" "include \"benchmark\"; transfer_result(\"$1\";200;150000000;$2)"; }
printf '{"bytes":100000000,"seconds":8,"http":"200","contentLength":150000000,"contentType":"application/octet-stream"}\n' | classify download 28 > "$work/slow.json"
jq -e '.status=="time-limit" and .throughputMbps==100 and .validMeasurement' "$work/slow.json" >/dev/null
printf 'PASS partial download retains measured 100 Mbps at the time limit\n'
printf '{"bytes":1024,"seconds":1,"http":"200","contentLength":1024,"contentType":"text/html"}\n' | classify download 0 > "$work/small.json"
jq -e '.status=="endpoint-contract-invalid" and .throughputMbps==null and (.validMeasurement|not)' "$work/small.json" >/dev/null
printf 'PASS small HTTP200 error page is not a valid throughput measurement\n'
printf '{"bytes":150000000,"seconds":6,"http":"200","contentLength":150000000,"contentType":"application/octet-stream"}\n' | classify download 0 > "$work/full.json"
jq -e '.status=="complete" and .throughputMbps==200' "$work/full.json" >/dev/null
printf 'PASS complete download validates exact response size\n'
printf '{"bytes":100000000,"seconds":8,"http":"000"}\n' | classify upload 28 > "$work/upload.json"
jq -e '.status=="time-limit-unconfirmed" and .throughputMbps==100 and (.validMeasurement|not)' "$work/upload.json" >/dev/null
printf 'PASS partial upload is retained but explicitly unconfirmed by server\n'
printf '{"bytes":150000000,"seconds":6,"http":"200","serverReceivedBytes":150000000}\n' | classify upload 0 > "$work/ack.json"
jq -e '.status=="complete" and .validMeasurement' "$work/ack.json" >/dev/null
printf 'PASS upload completion requires server acknowledgement of bytes\n'
jq -n '[range(0;3)|{wallUs:(.*1000000),hostTotal:(.*100),hostBusy:(.*50),hostSteal:(.*20),serviceCpuUs:(.*250000),servicePid:123,serviceRssKiB:(100+.*50),hostUsedRamKiB:500}]' > "$work/resources.json"
jq -L "$SFXH_CODE/templates" 'include "benchmark";resource_summary' "$work/resources.json" > "$work/summary.json"
jq -e '.serviceCpuAveragePercent==25 and .hostCpuAveragePercent==50 and .stealAveragePercent==20 and .serviceRssPeakKiB==200' "$work/summary.json" >/dev/null
printf 'PASS service CPU, host CPU and steal are separated per stage\n'
jq '.[2].servicePid=456' "$work/resources.json" | jq -L "$SFXH_CODE/templates" 'include "benchmark";resource_summary' > "$work/reset.json"
jq -e '.serviceCpuAveragePercent==null' "$work/reset.json" >/dev/null
printf 'PASS process replacement makes average unavailable, not invented\n'
df() { printf 'Filesystem 1024-blocks Used Available Capacity Mounted\nfixture 1000 999 1 99%% /\n'; }
if sf_require_space "$work" 524288 2>/dev/null; then exit 1; fi
printf 'PASS low disk space fails before download\n'
for rate in 100 150 200; do
    bytes=$(sf_bench_bytes download "$rate" "$SFXH_CODE/data/probes.json")
    ((bytes<100000000 && bytes>0))
done
[[ $(sf_bench_bytes upload 200 "$SFXH_CODE/data/probes.json") == 150000000 ]]
printf 'PASS high-rate downloads honor endpoint byte limit without changing upload budget\n'
jq '.performance.downloadMaxBytes=0' "$SFXH_CODE/data/probes.json" > "$work/invalid-endpoint.json"
if sf_bench_bytes download 200 "$work/invalid-endpoint.json" > /dev/null 2>&1; then exit 1; fi
printf 'PASS invalid endpoint byte budget fails before transfer\nTOTAL 10 reporting checks\n'
