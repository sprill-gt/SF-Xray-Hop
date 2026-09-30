def transfer_result($direction; $target; $requested; $rc):
  .http = (.http|tonumber? // 0) |
  . + {direction:$direction,targetMbps:$target,requestedBytes:$requested,curlExit:$rc} |
  (.seconds>0 and .bytes>0) as $partial |
  (.http>=200 and .http<300) as $http |
  (if $direction=="download" then .contentLength==$requested and ((.contentType//"")|startswith("application/octet-stream"))
   else .serverReceivedBytes==$requested end) as $contract |
  . + {status:(if $rc==0 and $http and $contract and .bytes==$requested then "complete"
    elif $rc==28 and $partial and $direction=="download" and $http and $contract and .bytes<=$requested then "time-limit"
    elif $rc==28 and $partial and $direction=="upload" then "time-limit-unconfirmed"
    elif $http and ($contract|not) then "endpoint-contract-invalid" else "transfer-failed" end)} |
  . + {measurementScope:(if .status=="time-limit-unconfirmed" then "client-sent-unconfirmed" elif .status=="complete" or .status=="time-limit" then "endpoint-validated" else "unconfirmed" end),
       throughputMbps:(if $partial and (.status=="complete" or .status=="time-limit" or .status=="time-limit-unconfirmed") then .bytes*8/.seconds/1000000 else null end),
       rawTransferredBytes:.bytes,validMeasurement:(.status=="complete" or .status=="time-limit")};
def mean: if length==0 then null else add/length end;
def peak: if length==0 then null else max end;
def resource_summary:
  . as $samples |
  [range(1;length) as $i | .[$i] as $b | .[$i-1] as $a |
    {wall:($b.wallUs-$a.wallUs),total:($b.hostTotal-$a.hostTotal),busy:($b.hostBusy-$a.hostBusy),steal:($b.hostSteal-$a.hostSteal),
     service:(if $b.serviceCpuUs!=null and $a.serviceCpuUs!=null and $b.servicePid==$a.servicePid and $b.serviceCpuUs>=$a.serviceCpuUs then $b.serviceCpuUs-$a.serviceCpuUs else null end)} |
    select(.wall>0 and .total>0)] as $d |
  {hostCpuAveragePercent:(if ($d|length)>0 then ($d|map(.busy)|add)*100/($d|map(.total)|add) else null end),
   hostCpuPeakPercent:($d|map(.busy*100/.total)|peak),
   stealAveragePercent:(if ($d|length)>0 then ($d|map(.steal)|add)*100/($d|map(.total)|add) else null end),
   stealPeakPercent:($d|map(.steal*100/.total)|peak),
   serviceCpuAveragePercent:(if ($d|length)>0 and all($d[];.service!=null) then ($d|map(.service)|add)*100/($d|map(.wall)|add) else null end),
   serviceCpuPeakPercent:($d|map(select(.service!=null)|.service*100/.wall)|peak),
   serviceRssAverageKiB:($samples|map(.serviceRssKiB|select(.!=null))|mean),
   serviceRssPeakKiB:($samples|map(.serviceRssKiB|select(.!=null))|peak),
   hostUsedRamPeakKiB:($samples|map(.hostUsedRamKiB)|peak),
   serviceCpuBasis:"一个逻辑CPU=100%；正式服务cgroup，不含额外探测客户端",
   serviceRssBasis:"正式服务cgroup进程RSS之和，包含共享页重复计数"};
