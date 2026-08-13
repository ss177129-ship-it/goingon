// 푸시 검증 도구 (일회용 — 저장소에 커밋하지 않음)
//
//   node push-check.js list          → 사용자별 등록된 기기 토큰 수
//   node push-check.js send <uid>    → 그 사용자에게 테스트 알림 발송
//
// ~/.secrets/goingon-firebase-adminsdk.json 의 관리자 키를 씁니다.
// 이 키는 보안 규칙을 우회하므로 절대 앱이나 저장소에 넣지 말 것.

const admin = require('firebase-admin');
const os = require('os');
const path = require('path');

admin.initializeApp({
  credential: admin.credential.cert(
    require(path.join(os.homedir(), '.secrets', 'goingon-firebase-adminsdk.json')),
  ),
});

const db = admin.firestore();
const [cmd, arg] = process.argv.slice(2);

async function list() {
  const snap = await db.collection('users').get();
  console.log(`사용자 ${snap.size}명\n`);
  for (const d of snap.docs) {
    const tokens = d.get('fcmTokens') ?? [];
    const mark = tokens.length > 0 ? '✅' : '  ';
    console.log(
      `${mark} ${(d.get('name') ?? '(이름없음)').padEnd(10)} ` +
        `@${(d.get('username') ?? '-').padEnd(16)} ` +
        `기기 ${tokens.length}대  uid=${d.id}`,
    );
  }
}

async function send(uid) {
  if (!uid) throw new Error('uid를 넣어주세요');
  const snap = await db.collection('users').doc(uid).get();
  const tokens = snap.get('fcmTokens') ?? [];
  const name = snap.get('name') ?? '(이름없음)';
  if (tokens.length === 0) {
    console.log(`❌ ${name}: 등록된 기기가 없습니다. 폰에서 앱을 켜고 알림을 허용했는지 확인하세요.`);
    return;
  }
  console.log(`${name}의 기기 ${tokens.length}대로 발송합니다…`);

  const res = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {
      title: '지금 같이 달릴까요?',
      body: '푸시가 정상으로 도착했습니다',
    },
    data: { type: 'runRequest' },
    apns: {
      headers: { 'apns-push-type': 'alert', 'apns-priority': '10' },
      payload: { aps: { sound: 'default', 'interruption-level': 'time-sensitive' } },
    },
  });

  res.responses.forEach((r, i) => {
    const t = tokens[i].slice(0, 14) + '…';
    console.log(r.success ? `  ✅ ${t} 전송됨` : `  ❌ ${t} ${r.error?.code}: ${r.error?.message}`);
  });
  console.log(`\n성공 ${res.successCount} / 실패 ${res.failureCount}`);
}

(cmd === 'send' ? send(arg) : list())
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('오류:', e.message);
    process.exit(1);
  });
