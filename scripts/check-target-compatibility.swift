import Foundation
@main struct TargetCompatibilityChecks {
 static func main() throws {
  var total=0
  func check(_ label:String,_ value:@autoclosure () throws -> Bool) throws { total += 1; guard try value() else { fatalError("Synthetic failure: "+label) } }
  let uuid="11111111-1111-4111-8111-111111111111"
  let reality="vless://\(uuid)@node.example.invalid:443?encryption=none&security=reality&type=grpc&flow=&fp=chrome&sni=tls.example.invalid&pbk=\(CompatibilityFixture.publicKey)&sid=0123456789abcdef&serviceName=fixture&mode=gun#Reality"
  let tuic="tuic://\(uuid):FAKE%3A%2B%40%26%25@node.example.invalid:443?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=tls.example.invalid&insecure=0#TUIC"
  let list=Data((reality+"\n"+tuic).utf8).base64EncodedString()
  let p=try PrototypeConfiguration.prepare(Data(list.utf8))
  try check("combined base64",p.catalog.nodes.count == 2 && p.insecureNodeCount == 0)
  try check("full diagnostics",ConfigurationCompatibility.inspect(Data(list.utf8)).canUse)
  let runtime=try JSONSerialization.jsonObject(with:Data(p.runtimeJSON.utf8)) as! [String:Any]
  let nodes=runtime["proxies"] as! [[String:Any]]
  try check("Reality keeps gRPC",nodes[0]["network"] as? String == "grpc" && nodes[0]["reality-opts"] != nil)
  try check("TUIC credentials preserved",nodes[1]["password"] as? String == "FAKE:+@&%")
  try check("TUIC relay preserved",nodes[1]["udp-relay-mode"] as? String == "native" && nodes[1]["congestion-controller"] as? String == "bbr")
  for bad in [reality.replacingOccurrences(of:"flow=&",with:"flow=xtls-rprx-vision&"),tuic.replacingOccurrences(of:"#TUIC",with:"&UNKNOWN=value#TUIC"),tuic.replacingOccurrences(of:"congestion_control=bbr",with:"congestion_control=unknown"),tuic.replacingOccurrences(of:uuid,with:"invalid")] {
   try check("invalid protocol fields blocked",(try? NodeURI.parse(bad,index:0)) == nil)
  }
  let insecure=tuic.replacingOccurrences(of:"insecure=0",with:"insecure=1")
  let prepared=try PrototypeConfiguration.prepare(Data(insecure.utf8))
  try check("insecure import allowed",prepared.insecureNodeCount == 1)
  var stored=StoredConfiguration(source:prepared.source)
  try check("default consent denied",(try? stored.requireCertificateConsent(for:prepared)) == nil)
  stored.certificateConsentDigest=stored.contentDigest
  try stored.requireCertificateConsent(for:prepared)
  let decoded=try JSONDecoder().decode(StoredConfiguration.self,from:JSONEncoder().encode(stored))
  try check("consent persistence",decoded.certificateConsentDigest == stored.contentDigest)
  var changed=StoredConfiguration(source:Data((insecure+"\n").utf8));changed.certificateConsentDigest=stored.contentDigest
  try check("changed source invalidates consent",(try? changed.requireCertificateConsent(for:prepared)) == nil)
  let storage=MemorySubscriptionStorage(), repository=SubscriptionRepository(storage:storage)
  let id=try repository.add(StoredConfiguration(source:prepared.source),fileName:"example.yaml",nodeCount:1,groupCount:1,ruleCount:1,makeCurrent:true)
  let before=try repository.record(id)
  try check("repository defaults deny",before.certificateConsentDigest == nil)
  try check("stale approval rejected",(try? repository.approveInsecureCertificates(id,expectedDigest:"stale")) == nil)
  try repository.approveInsecureCertificates(id,expectedDigest:before.contentDigest)
  try repository.record(id).requireCertificateConsent(for:prepared)
  try repository.saveChoices(["Imported":"TUIC"],for:id)
  let approved=try repository.record(id)
  try check("node switching preserves content consent",approved.certificateConsentDigest == approved.contentDigest)
  try repository.replace(id,expected:approved,source:changed.source,choices:approved.choices,sourceURL:nil,nodeCount:1,groupCount:1,ruleCount:1)
  try check("revision update clears consent",try repository.record(id).certificateConsentDigest == nil)
  let rules=["PROCESS-NAME,ExampleDesktop,DIRECT","IP-CIDR,2001:db8::/32,DIRECT,no-resolve","DOMAIN-SUFFIX,例子.测试,DIRECT","MATCH,Imported"]
  var root=try PrototypeConfiguration.decode(Data(tuic.utf8));root["rules"]=rules
  let mixed=try PrototypeConfiguration.prepare(JSONSerialization.data(withJSONObject:root))
  let generated=try JSONSerialization.jsonObject(with:Data(mixed.runtimeJSON.utf8)) as! [String:Any]
  let active=generated["rules"] as! [String]
  try check("process rule removed only at runtime",active.count == 3 && !active.contains{$0.hasPrefix("PROCESS-NAME,")})
  try check("iOS adaptation reported",mixed.adaptations.contains{$0.contains("PROCESS-NAME")})
  try check("original rules preserved",(try PrototypeConfiguration.decode(mixed.source)["rules"] as? [String]) == rules)
  try check("IDNA conversion",active.contains("DOMAIN-SUFFIX,xn--fsqu00a.xn--0zwm56d,DIRECT"))
  try check("IPv6 CIDR alias",active.contains("IP-CIDR,2001:db8::/32,DIRECT,no-resolve"))
  try check("malformed CIDR blocked",(try? ConfigurationRules.validate(["IP-CIDR,2001:db8::/129,DIRECT","MATCH,DIRECT"],targets:["DIRECT"])) == nil)
  try check("process references still checked",(try? ConfigurationRules.validate(["PROCESS-NAME,Example,MISSING","MATCH,DIRECT"],targets:["DIRECT"])) == nil)
  try Data(p.runtimeJSON.utf8).write(to:URL(fileURLWithPath:".build/research/target-protocols-runtime.json"))
  try Data(mixed.runtimeJSON.utf8).write(to:URL(fileURLWithPath:".build/research/target-rules-runtime.json"))
  for sample in CompatibilitySamples.all where ["reality-grpc-tuic", "ios-process-idna"].contains(sample.id) {
   try check("sample validates",ConfigurationCompatibility.inspect(Data(sample.yaml.utf8)).canUse)
   try Data(sample.yaml.utf8).write(to:URL(fileURLWithPath:"Examples/compatibility/"+sample.id+".yaml"))
  }
  print("Target compatibility: \(total) synthetic checks passed; no external network or persistent credentials.")
 }
}
