// 페이스메이트 관계 쓰기 규칙 — expand 단계(friends + follows 공존).
//
// 여기서 지키는 것은 하나다: **수락 없이는 관계가 생기지 않는다.**
// 검색이 열려 있는 동안 수락이 유일한 프라이버시 장치라, 이 규칙이 뚫리면
// 아이디를 아는 사람이 곧 남의 고스트를 볼 수 있는 사람이 된다.
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  arrayRemove,
  arrayUnion,
  deleteDoc,
  doc,
  getDoc,
  setDoc,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';

const A = 'aaa'; // 요청을 보낸 사람
const B = 'bbb'; // 수락하는 사람
const C = 'ccc'; // 무관한 사람

let env;

const edge = (from, to) => `${from}_${to}`;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'goingon-rules-test',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await env?.cleanup();
});

/** 매번 깨끗한 상태에서 시작한다 — 앞 테스트가 만든 관계가 남으면 판정이 흐려진다 */
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', A), { name: 'A' });
    await setDoc(doc(db, 'users', B), { name: 'B' });
    await setDoc(doc(db, 'users', C), { name: 'C' });
    // A가 B에게 보낸 대기 중 요청 (문서의 존재 자체가 '대기 중')
    await setDoc(doc(db, 'friendRequests', edge(A, B)), {
      fromUid: A,
      toUid: B,
      cheer: 'cheer',
    });
  });
});

/** 앱의 acceptRequest가 실제로 던지는 배치와 같은 모양 */
function acceptBatch(db, me, from) {
  const batch = writeBatch(db);
  batch.delete(doc(db, 'friendRequests', edge(from, me)));
  batch.set(doc(db, 'follows', edge(from, me)), {
    followerUid: from,
    followeeUid: me,
  });
  batch.set(doc(db, 'follows', edge(me, from)), {
    followerUid: me,
    followeeUid: from,
  });
  batch.update(doc(db, 'users', me), {
    friends: arrayUnion(from),
    following: arrayUnion(from),
  });
  batch.update(doc(db, 'users', from), {
    friends: arrayUnion(me),
    following: arrayUnion(me),
  });
  return batch;
}

describe('페이스메이트 맺기 — 수락이 유일한 문', () => {
  it('요청이 있으면 수락이 통과한다 (양쪽 간선 + 양쪽 배열)', async () => {
    const db = env.authenticatedContext(B).firestore();
    await assertSucceeds(acceptBatch(db, B, A).commit());
  });

  it('요청이 없으면 수락 배치가 통째로 막힌다', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await deleteDoc(doc(ctx.firestore(), 'friendRequests', edge(A, B)));
    });
    const db = env.authenticatedContext(B).firestore();
    await assertFails(acceptBatch(db, B, A).commit());
  });

  it('요청 없이 간선만 몰래 만들 수 없다', async () => {
    const db = env.authenticatedContext(C).firestore();
    await assertFails(
      setDoc(doc(db, 'follows', edge(C, A)), {
        followerUid: C,
        followeeUid: A,
      }),
    );
  });

  it('문서 id와 내용이 어긋난 간선은 거부된다', async () => {
    const db = env.authenticatedContext(B).firestore();
    await assertFails(
      setDoc(doc(db, 'follows', edge(A, B)), {
        followerUid: C,
        followeeUid: B,
      }),
    );
  });

  it('요청 없이 남의 목록에 나를 밀어넣을 수 없다', async () => {
    const db = env.authenticatedContext(C).firestore();
    await assertFails(
      updateDoc(doc(db, 'users', A), {
        friends: arrayUnion(C),
        following: arrayUnion(C),
      }),
    );
  });

  it('두 배열에 서로 다른 사람을 넣을 수 없다', async () => {
    const db = env.authenticatedContext(B).firestore();
    await assertFails(
      updateDoc(doc(db, 'users', B), {
        friends: arrayUnion(A),
        following: arrayUnion(C),
      }),
    );
  });
});

describe('끊기 — 이관 중에도 막히지 않아야 한다', () => {
  it('양쪽 구조가 다 있는 관계를 끊는다', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'users', A), { name: 'A', friends: [B], following: [B] });
      await setDoc(doc(db, 'users', B), { name: 'B', friends: [A], following: [A] });
    });
    const db = env.authenticatedContext(B).firestore();
    const batch = writeBatch(db);
    batch.update(doc(db, 'users', B), {
      friends: arrayRemove(A),
      following: arrayRemove(A),
    });
    batch.update(doc(db, 'users', A), {
      friends: arrayRemove(B),
      following: arrayRemove(B),
    });
    await assertSucceeds(batch.commit());
  });

  it('아직 이관되지 않은 계정(following 없음)도 끊을 수 있다', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'users', A), { name: 'A', friends: [B] });
      await setDoc(doc(db, 'users', B), { name: 'B', friends: [A] });
    });
    const db = env.authenticatedContext(B).firestore();
    const batch = writeBatch(db);
    batch.update(doc(db, 'users', B), {
      friends: arrayRemove(A),
      following: arrayRemove(A),
    });
    batch.update(doc(db, 'users', A), {
      friends: arrayRemove(B),
      following: arrayRemove(B),
    });
    await assertSucceeds(batch.commit());
  });

  it('차단은 관계를 함께 끊는다', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'users', B), { name: 'B', friends: [A], following: [A] });
    });
    const db = env.authenticatedContext(B).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'users', B), {
        blocked: arrayUnion(A),
        friends: arrayRemove(A),
        following: arrayRemove(A),
      }),
    );
  });

  it('차단하면서 관계를 늘릴 수는 없다', async () => {
    const db = env.authenticatedContext(B).firestore();
    await assertFails(
      updateDoc(doc(db, 'users', B), {
        blocked: arrayUnion(A),
        friends: arrayUnion(C),
        following: arrayUnion(C),
      }),
    );
  });
});

describe('간선은 당사자만 본다', () => {
  it('내가 낀 간선은 읽힌다', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'follows', edge(A, B)), {
        followerUid: A,
        followeeUid: B,
      });
    });
    const db = env.authenticatedContext(B).firestore();
    await assertSucceeds(getDoc(doc(db, 'follows', edge(A, B))));
  });

  it('남의 간선은 읽을 수 없다', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'follows', edge(A, B)), {
        followerUid: A,
        followeeUid: B,
      });
    });
    const db = env.authenticatedContext(C).firestore();
    await assertFails(getDoc(doc(db, 'follows', edge(A, B))));
  });
});
