// firestore.rules 회귀 테스트 — 에뮬레이터에서만 돈다.
//
// 왜 필요한가: 규칙이 틀리면 증상이 **조용하다.** 느슨하면 아무도 모르는 채로
// 남의 기록이 읽히고, 빡빡하면 목록이 그냥 비어 보인다(에러 화면도 안 뜬다).
// 둘 다 로그에 안 남는다.
//
// 특히 `runs` 목록 쿼리는 실기기로 검증하기가 어렵다 — 페이스메이트 갈래를
// 지나가려면 **상대 계정에 실제 러닝 문서가 있어야** 하기 때문이다. 여기서는
// 계정을 원하는 만큼 만들 수 있어서 그 갈래를 처음으로 실제로 밟는다.
//
// 실행: cd test_rules && npm test
import { readFileSync } from 'node:fs';
import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  setDoc,
  where,
} from 'firebase/firestore';

const ME = 'me';
const MATE = 'mate';        // 나와 서로 페이스메이트
const STRANGER = 'stranger'; // 아무 사이도 아님

let env;

/** 규칙을 끄고 만드는 씨앗 데이터 — 준비 과정이 규칙에 막히면 안 된다 */
async function seed() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', ME), { name: '나', friends: [MATE] });
    await setDoc(doc(db, 'users', MATE), { name: '메이트', friends: [ME] });
    await setDoc(doc(db, 'users', STRANGER), { name: '남', friends: [] });

    const run = (uid, visibility, i) => ({
      uid,
      startedAt: new Date(2026, 7, 20 + i).toISOString(),
      seconds: 480,
      km: 1.4,
      kcal: 90,
      cadence: [0, 1, -1],
      visibility,
      createdAt: new Date(2026, 7, 20 + i),
    });

    await setDoc(doc(db, 'runs', 'mine-public'), run(ME, 'everyone', 0));
    await setDoc(doc(db, 'runs', 'mine-private'), run(ME, 'private', 1));
    await setDoc(doc(db, 'runs', 'mate-shared'), run(MATE, 'pacemates', 2));
    await setDoc(doc(db, 'runs', 'mate-private'), run(MATE, 'private', 3));
    await setDoc(doc(db, 'runs', 'stranger-shared'), run(STRANGER, 'pacemates', 4));
  });
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'goingon-rules-test',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
  await env.clearFirestore();
  await seed();
});

after(async () => {
  await env?.cleanup();
});

/** 앱이 실제로 던지는 쿼리와 같은 모양이어야 의미가 있다 */
const sharedVisibility = ['pacemates', 'everyone'];

describe('runs 목록 — 고스트 서랍이 보는 것', () => {
  it('내 런은 비공개까지 전부 보인다', async () => {
    const db = env.authenticatedContext(ME).firestore();
    const snap = await assertSucceeds(
      getDocs(query(
        collection(db, 'runs'),
        where('uid', '==', ME),
        orderBy('createdAt', 'desc'),
        limit(20),
      )),
    );
    assert.equal(snap.size, 2, '내 것은 공개 범위와 무관하게 다 보여야 한다');
  });

  it('페이스메이트의 공유된 런이 보인다 — 실기기로 못 밟던 갈래', async () => {
    const db = env.authenticatedContext(ME).firestore();
    const snap = await assertSucceeds(
      getDocs(query(
        collection(db, 'runs'),
        where('uid', 'in', [MATE]),
        where('visibility', 'in', sharedVisibility),
        orderBy('createdAt', 'desc'),
        limit(20),
      )),
    );
    assert.equal(snap.size, 1);
    assert.equal(snap.docs[0].id, 'mate-shared');
  });

  // ── 여기서 실제 구멍을 잡았다(2026-08-23) ──
  // 목록 평가에서 resource.data는 문서 내용이 아니라 쿼리 조건으로 채워진다.
  // 규칙이 `.get('visibility','pacemates')`처럼 기본값을 쓰고 있으면, 공개
  // 범위를 안 좁힌 쿼리가 기본값으로 통과해 **비공개 런이 새어 나온다.**

  it('공개 범위를 안 좁힌 쿼리는 거부된다 — 비공개가 새지 않게', async () => {
    const db = env.authenticatedContext(ME).firestore();
    await assertFails(
      getDocs(query(collection(db, 'runs'), where('uid', '==', MATE))),
    );
  });

  it('비공개를 대놓고 물어도 거부된다', async () => {
    const db = env.authenticatedContext(ME).firestore();
    await assertFails(
      getDocs(query(
        collection(db, 'runs'),
        where('uid', '==', MATE),
        where('visibility', '==', 'private'),
      )),
    );
  });

  it('문서 하나를 직접 읽는 것도 막힌다', async () => {
    const db = env.authenticatedContext(ME).firestore();
    await assertFails(getDoc(doc(db, 'runs', 'mate-private')));
  });

  it('페이스메이트가 아닌 사람의 런은 필터를 걸어도 거부된다', async () => {
    const db = env.authenticatedContext(ME).firestore();
    await assertFails(
      getDocs(query(
        collection(db, 'runs'),
        where('uid', 'in', [STRANGER]),
        where('visibility', 'in', sharedVisibility),
        orderBy('createdAt', 'desc'),
        limit(20),
      )),
    );
  });

  it('조건 없이 전체를 훑을 수 없다', async () => {
    const db = env.authenticatedContext(ME).firestore();
    await assertFails(getDocs(query(collection(db, 'runs'), limit(50))));
  });

  it('로그인하지 않으면 아무것도 못 읽는다', async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(
      getDocs(query(collection(db, 'runs'), where('uid', '==', ME), limit(5))),
    );
  });
});
