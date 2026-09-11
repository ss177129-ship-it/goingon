#!/usr/bin/env python3
# APNs 키가 살아 있는지 애플에 직접 물어본다 (Firebase를 거치지 않고).
#
#   python3 tools/apns-probe.py <키ID> <팀ID> <p8경로> <호스트>
#   python3 tools/apns-probe.py 4FX4S6SZNR R4JD49GK34 ~/.secrets/apple/AuthKey_4FX4S6SZNR.p8 api.push.apple.com
#
# 일부러 가짜 디바이스 토큰(0×64)으로 보낸다. 그래서 응답이 곧 판정이다:
#   400 BadDeviceToken      → 키·팀ID·키ID 인증은 통과했다 (토큰만 가짜)
#   403 InvalidProviderToken → 키가 틀렸다 (APNs 키가 아니거나 폐기됐거나 팀ID 불일치)
#
# 2026-09-11: FCM이 "Invalid APNs credential"을 돌려줬을 때, 로컬 키는 이걸로
# 정상임이 확인됐고 콘솔에 올라간 쪽이 문제라는 판정이 났다. FCM 오류만 봐서는
# 키 파일이 잘못인지 콘솔 등록이 잘못인지 알 수 없다 — 이 스크립트가 그 둘을 가른다.
# 의존성 없음: openssl(ES256 서명)과 curl(HTTP/2)만 쓴다.
kid, team, p8, host = sys.argv[1:5]
def b64(b): return base64.urlsafe_b64encode(b).rstrip(b'=')
hdr = b64(json.dumps({"alg":"ES256","kid":kid}).encode())
pl  = b64(json.dumps({"iss":team,"iat":int(time.time())}).encode())
msg = hdr+b'.'+pl
with tempfile.NamedTemporaryFile(delete=False) as f: f.write(msg); mp=f.name
der = subprocess.check_output(["openssl","dgst","-sha256","-sign",p8,mp]); os.unlink(mp)
def parse(d):
    i=2; assert d[i]==2; l=d[i+1]; r=d[i+2:i+2+l]; i+=2+l; assert d[i]==2; l=d[i+1]; s=d[i+2:i+2+l]
    return r[-32:].rjust(32,b'\0')+s[-32:].rjust(32,b'\0')
jwt=(msg+b'.'+b64(parse(der))).decode()
tok="00"*32
out = subprocess.run(["curl","-s","--http2","-o","/dev/stdout","-w","\nHTTP %{http_code}",
  "-H","authorization: bearer "+jwt,"-H","apns-topic: com.chanwoong.goingon","-H","apns-push-type: alert",
  "-d",'{"aps":{"alert":"probe"}}',f"https://{host}/3/device/{tok}"],capture_output=True,text=True)
print(out.stdout.strip() or out.stderr.strip())
