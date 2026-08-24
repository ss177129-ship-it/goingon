// friends 배열 → follows 간선 + following 배열 이관 (P6.5, expand-migrate-contract의 ②).
//
//   node tools/migrate-follows.js            → 무엇이 바뀔지만 보여줌
//   node tools/migrate-follows.js --apply    → 실제로 씀
//
// ~/.secrets/goingon-firebase-adminsdk.json 의 관리자 키를 쓴다. 이 키는
// 보안 규칙을 우회하므로 절대 앱이나 저장소에 넣지 말 것.
//
// **여러 번 돌려도 안전하다**(멱등). 이미 있는 간선은 merge로 덮고, 배열은
// arrayUnion이라 중복이 생기지 않는다. 이관 중에 앱이 계속 돌아도 되게
// 만든 이유는 expand 단계의 앱이 두 구조의 합집합을 읽기 때문이다 —
// 이관 전/도중/후 어느 시점에도 목록이 비지 않는다.
//
// 실행: cd functions && NODE_PATH=./node_modules node ../tools/migrate-follows.js
const admin = require('firebase-admin');
const os = require('os');
const path = require('path');

admin.initializeApp({
  credential: admin.credential.cert(
    require(path.join(os.homedir(), '.secrets', 'goingon-firebase-adminsdk.json')),
  ),
});

const db = admin.firestore();
const apply = process.argv.includes('--apply');

const edgeId = (follower, followee) => `${follower}_${followee}`;

async function main() {
  const users = await db.collection('users').get();
  const existing = new Set(
    (await db.collection('follows').get()).docs.map((d) => d.id),
  );
  // 살아 있는 계정만. friends에는 탈퇴한 사람의 uid가 남아 있을 수 있고
  // (실제로 하나 있었다), 그런 참조를 새 구조로 옮기면 아무도 아닌 상대와
  // 맺어진 간선이 생긴다. 옮기지 않고 보고만 한다
  const alive = new Set(users.docs.map((d) => d.id));

  let missingEdges = 0;
  let missingFollowing = 0;
  let orphanFollowing = 0;
  let danglingRefs = 0;
  const writes = [];

  for (const user of users.docs) {
    const uid = user.id;
    const all = user.get('friends') ?? [];
    const friends = all.filter((f) => alive.has(f));
    const dangling = all.filter((f) => !alive.has(f));
    if (dangling.length > 0) {
      danglingRefs += dangling.length;
      console.log(
        `  ! ${label(user)} — 없는 계정 참조(옮기지 않음): ${dangling.join(', ')}`,
      );
    }
    const following = user.get('following') ?? [];

    // following에만 있고 friends에 없는 것 — 아직 있을 수 없지만, 있으면
    // 사람이 봐야 하는 상태다(수동으로 만든 간선 등)
    const orphans = following.filter((f) => !friends.includes(f));
    if (orphans.length > 0) {
      orphanFollowing += orphans.length;
      console.log(
        `  ? ${label(user)} — following에만 있음: ${orphans.join(', ')}`,
      );
    }

    const addToFollowing = friends.filter((f) => !following.includes(f));
    const edgesToMake = friends
      .map((f) => edgeId(uid, f))
      .filter((id) => !existing.has(id));

    if (addToFollowing.length === 0 && edgesToMake.length === 0) continue;

    missingFollowing += addToFollowing.length;
    missingEdges += edgesToMake.length;
    console.log(
      `  · ${label(user)} — following +${addToFollowing.length}, 간선 +${edgesToMake.length}`,
    );

    if (!apply) continue;

    if (addToFollowing.length > 0) {
      writes.push(
        user.ref.update({
          following: admin.firestore.FieldValue.arrayUnion(...addToFollowing),
        }),
      );
    }
    for (const f of friends) {
      const id = edgeId(uid, f);
      if (existing.has(id)) continue;
      writes.push(
        db.collection('follows').doc(id).set(
          {
            followerUid: uid,
            followeeUid: f,
            // 언제 맺어졌는지는 이제 알 수 없다. 이관 시각을 남기면
            // "그때 맺었다"는 거짓이 되므로 표시만 남긴다
            migratedFromFriends: true,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        ),
      );
      existing.add(id);
    }
  }

  await Promise.all(writes);

  console.log('');
  console.log(`사용자 ${users.size}명`);
  console.log(`following 채울 항목: ${missingFollowing}`);
  console.log(`만들 간선: ${missingEdges}`);
  if (danglingRefs > 0) {
    console.log(
      `없는 계정 참조: ${danglingRefs} — friends에 남은 유령이다. 앱은 이미 무시하므로 급하지 않다`,
    );
  }
  if (orphanFollowing > 0) {
    console.log(`following에만 있는 항목: ${orphanFollowing} (사람이 확인할 것)`);
  }
  console.log(apply ? '→ 적용했습니다.' : '→ --apply 를 붙이면 실제로 씁니다.');
}

function label(user) {
  const name = user.get('name') ?? '(이름없음)';
  const username = user.get('username') ?? '-';
  return `${name} @${username}`;
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
