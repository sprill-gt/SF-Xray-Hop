def uuid: type == "string" and test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$");
def clean: type == "string" and (test("[\\x00-\\x1f\\x7f]")|not);
def display_name: type=="string" and length>0 and length<=80 and utf8bytelength<=240 and
  (test("[\\p{Cc}\\p{Cf}\\p{Zl}\\p{Zp}]")|not);
def node_role: if .nextHop!=null then "entry" else (.presentation.role // "standalone") end;
def downstream_name: .presentation.downstreamName // "下游节点";
# An explicit predicate, shared by import and persistent-state validation.
def valid_profile:
  type=="object" and (.address|clean and length>0) and
  (.port|type=="number" and floor==. and .>=1 and .<=65535) and (.id|uuid) and
  (.encryption|clean and length>40 and .!="none") and .flow=="xtls-rprx-vision" and
  .network=="xhttp" and .security=="reality" and
  (.serverName|clean and length>0) and (.fingerprint=="chrome" or .fingerprint=="firefox" or .fingerprint=="safari") and
  (.password|test("^[A-Za-z0-9_-]{43}$")) and
  (.shortId|test("^([0-9a-fA-F]{2}){0,8}$")) and
  (.path|clean and startswith("/")) and .mode=="auto" and (.remark|clean);
def public_profile($s; $which):
  {address:$s.node.address,port:$s.node.port,id:$s.identities[$which].id,
   encryption:$s.encryption.encryption,flow:"xtls-rprx-vision",network:"xhttp",security:"reality",
   serverName:$s.reality.serverName,password:$s.reality.password,shortId:$s.reality.shortId,
   fingerprint:$s.fingerprint,path:$s.xhttp.path,mode:"auto",
   remark:(if $which=="direct" then "直连 | "+$s.node.name
     elif ($s|node_role)=="entry" then "链式 | "+$s.node.name+"→"+($s|downstream_name)
     else "对接 | "+$s.node.name end)};
def valid_presentation:
  (.presentation|type=="object") and
  (if .nextHop!=null then .presentation.role=="entry" else
    (.presentation.role=="standalone" or .presentation.role=="exit") end) and
  (.presentation.downstreamName==null or (.presentation.downstreamName|display_name)) and
  (.nextHop==null or (.presentation.downstreamName|display_name)) and
  (.presentation.entry==null or (.presentation.entry|
    .source=="user" and (.address|clean and length>0) and (.name==null or (.name|display_name))));
def valid_state:
  . as $s | (.schemaVersion==1 or (.schemaVersion==2 and valid_presentation)) and (.node.name|display_name) and
  (.node.id|uuid) and (.encryption.rtt=="0" or .encryption.rtt=="1") and
  .encryption.authentication=="ML-KEM-768" and
  (.encryption.decryption|clean and length>40) and (.encryption.generatorDecryption|clean and length>40) and
  (.reality.privateKey|test("^[A-Za-z0-9_-]{43}$")) and (.reality.target|clean and length>0) and
  .identities.direct.email=="sf-xray-hop-direct" and .identities.relay.email=="sf-xray-hop-relay" and
  .identities.direct.id!=.identities.relay.id and
  (.core.id|test("^v[0-9]+\\.[0-9]+\\.[0-9]+-[a-f0-9]{16}$")) and
  (.core.version|test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
  (.core.channel=="pre" or .core.channel=="stable" or .core.channel=="pinned") and
  (public_profile($s;"direct")|valid_profile) and (public_profile($s;"relay")|valid_profile) and
  (.nextHop==null or (.nextHop|valid_profile));
def outbound($p; $tag):
  {tag:$tag,protocol:"vless",settings:{address:$p.address,port:$p.port,id:$p.id,encryption:$p.encryption,flow:$p.flow},
   streamSettings:{network:"xhttp",security:"reality",realitySettings:{serverName:$p.serverName,fingerprint:$p.fingerprint,password:$p.password,shortId:$p.shortId},
    xhttpSettings:{path:$p.path,mode:$p.mode}}};
def server_config($s):
  {log:{access:"none",loglevel:"warning"},
   inbounds:[{tag:"sf-xray-hop-in",listen:"::",port:$s.node.port,protocol:"vless",
    settings:{clients:[$s.identities.direct,$s.identities.relay]|map(.+{flow:"xtls-rprx-vision"}),decryption:$s.encryption.decryption},
    streamSettings:{network:"xhttp",security:"reality",xhttpSettings:$s.xhttp,
     realitySettings:{show:false,target:$s.reality.target,serverNames:[$s.reality.serverName],privateKey:$s.reality.privateKey,shortIds:[$s.reality.shortId]}}}],
   outbounds:([{tag:"reject",protocol:"blackhole"},{tag:"direct-freedom",protocol:"freedom"}]+if $s.nextHop==null then [] else [outbound($s.nextHop;"sf-xray-hop-next-hop")] end),
   routing:{domainStrategy:"AsIs",rules:[
    {type:"field",inboundTag:["sf-xray-hop-in"],user:["sf-xray-hop-direct"],outboundTag:"direct-freedom"},
    {type:"field",inboundTag:["sf-xray-hop-in"],user:["sf-xray-hop-relay"],outboundTag:(if $s.nextHop==null then "direct-freedom" else "sf-xray-hop-next-hop" end)},
    {type:"field",inboundTag:["sf-xray-hop-in"],outboundTag:"reject"}]}};
def client_config($p; $port):
  {log:{access:"none",loglevel:"warning"},inbounds:[{tag:"local-http",listen:"127.0.0.1",port:$port,protocol:"http",settings:{}}],
   outbounds:[outbound($p;"proxy")],routing:{rules:[{type:"field",inboundTag:["local-http"],outboundTag:"proxy"}]}};
