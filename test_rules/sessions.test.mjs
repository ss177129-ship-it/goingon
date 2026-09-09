// 세션 상태 전이 규칙 (2026-09-09 개편).
//
//   invited ──수락──▶ accepted ──둘 다 ready──▶ running ──▶ finished
//      │                  │
//      ├─거절─▶ declined   └─나감─▶ cancelled
//      └─만료─▶ expired
//
// **여기는 그동안 그물이 없던 자리다.** 규칙 회귀 테스트 21개는 runs 목록과
// 관계만 덮었고, 세션은 status가 허용 목록에만 들어 있으면 어디로든 갈 수
// 있었다 — 호스트가 자기 요청을 스스로 수락하거나, 끝난 세션을 되살리는 것도
// 규칙상 막히지 않았다. 화면으로는 재현하기 어려운 갈래라 여기서 못박는다.
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  addDoc,
  collection,
  doc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

const HOST = 'host';
const GUEST = 'guest';
const OTHER = 'other'; // 아무 상관 없는 사람
const SID = 'sess1';

let env;

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

/** 주어진 상태의 세션 하나를 규칙 밖에서 심어 둔다 */
async function seed(status, extra = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    // 호스트는 게스트를 이미 페이스메이트로 두고 있다(생성 규칙이 요구)
    await setDoc(doc(db, 'users', HOST), { name: 'H', following: [GUEST] });
    await setDoc(doc(db, 'users', GUEST), { name: 'G', following: [HOST] });
    await setDoc(doc(db, 'users', OTHER), { name: 'O' });
    await setDoc(doc(db, 'sessions', SID), {
      hostId: HOST,
      guestId: GUEST,
      participants: [HOST, GUEST],
      status,
      ready: { [HOST]: false, [GUEST]: false },
      ...extra,
    });
  });
}

const as = (uid) => env.authenticatedContext(uid).firestore();
const session = (uid) => doc(as(uid), 'sessions', SID);

beforeEach(async () => {
  await env.clearFirestore();
});

describe('요청 만들기', () => {
  it('페이스메이트에게 invited로 보낼 수 있다', async () => {
    await seed('invited');
    await assertSucceeds(
      addDoc(collection(as(HOST), 'sessions'), {
        hostId: HOST,
        guestId: GUEST,
        participants: [HOST, GUEST],
        status: 'invited',
        ready: { [HOST]: false, [GUEST]: false },
      }),
    );
  });

  it('처음부터 수락된 상태로 만들 수 없다', async () => {
    // 이걸 열어 주면 호스트가 상대 동의 없이 로비를 세울 수 있다
    await seed('invited');
    await assertFails(
      addDoc(collection(as(HOST), 'sessions'), {
        hostId: HOST,
        guestId: GUEST,
        participants: [HOST, GUEST],
        status: 'accepted',
      }),
    );
  });

  it('페이스메이트가 아닌 사람에게는 보낼 수 없다', async () => {
    await seed('invited');
    await assertFails(
      addDoc(collection(as(HOST), 'sessions'), {
        hostId: HOST,
        guestId: OTHER,
        participants: [HOST, OTHER],
        status: 'invited',
      }),
    );
  });
});

describe('수락은 초대받은 쪽만 한다', () => {
  it('게스트는 수락할 수 있다', async () => {
    await seed('invited');
    await assertSucceeds(updateDoc(session(GUEST), { status: 'accepted' }));
  });

  it('호스트는 자기 요청을 스스로 수락할 수 없다', async () => {
    // 이 구멍이 열려 있으면 "상대의 수락과 무관하게 준비 단계로 넘어간다"가
    // 화면 문제가 아니라 데이터 문제가 된다
    await seed('invited');
    await assertFails(updateDoc(session(HOST), { status: 'accepted' }));
  });

  it('호스트는 거절도 대신할 수 없다', async () => {
    await seed('invited');
    await assertFails(updateDoc(session(HOST), { status: 'declined' }));
  });

  it('게스트는 한 줄 답장과 함께 거절한다', async () => {
    await seed('invited');
    await assertSucceeds(
      updateDoc(session(GUEST), {
        status: 'declined',
        declineMessage: '오늘은 쉬고 싶어요',
      }),
    );
  });

  it('답장은 거절에만 붙는다 — 취소나 만료에 끼워 넣을 수 없다', async () => {
    await seed('invited');
    await assertFails(
      updateDoc(session(HOST), {
        status: 'cancelled',
        declineMessage: '상대가 거절한 것처럼 보이게',
      }),
    );
  });

  it('호스트도 게스트도 그만둘 수는 있다', async () => {
    await seed('invited');
    await assertSucceeds(updateDoc(session(HOST), { status: 'cancelled' }));
    await seed('invited');
    await assertSucceeds(updateDoc(session(GUEST), { status: 'expired' }));
  });
});

describe('건너뛸 수 없다', () => {
  it('수락 없이 바로 달릴 수 없다', async () => {
    await seed('invited');
    await assertFails(updateDoc(session(HOST), { status: 'running' }));
    await assertFails(updateDoc(session(GUEST), { status: 'running' }));
  });

  it('수락 없이 바로 끝낼 수 없다', async () => {
    await seed('invited');
    await assertFails(updateDoc(session(HOST), { status: 'finished' }));
  });

  it('수락된 세션은 달릴 수 있다', async () => {
    await seed('accepted');
    await assertSucceeds(updateDoc(session(HOST), { status: 'running' }));
  });

  it('달리는 세션은 취소되지 않는다 — 기록이 통째로 날아간다', async () => {
    await seed('running');
    await assertFails(updateDoc(session(HOST), { status: 'cancelled' }));
    await assertFails(updateDoc(session(GUEST), { status: 'expired' }));
  });
});

describe('끝난 것은 끝이다', () => {
  const all = ['invited', 'accepted', 'running', 'finished', 'declined',
    'expired', 'cancelled'];

  for (const dead of ['finished', 'declined', 'expired', 'cancelled']) {
    it(`${dead} 세션은 다른 어떤 상태로도 못 간다`, async () => {
      await seed(dead);
      for (const next of all.filter((s) => s !== dead)) {
        await assertFails(updateDoc(session(HOST), { status: next }));
        await assertFails(updateDoc(session(GUEST), { status: next }));
      }
    });
  }

  it('끝난 세션에 같은 상태를 다시 쓰는 것은 막지 않는다', async () => {
    // 부활이 아니라 **재제출 경로**다. 결과 업로드가 실패해 다시 올릴 때
    // 그 쓰기는 status를 그대로 둔 채 results만 건드린다 — 여기를 막으면
    // 이미 저장된 기록을 다시 올리려던 사람이 권한 거부를 보게 된다.
    // 집계가 두 번 오르는 것은 규칙이 아니라 isFirstSubmit이 막는다
    await seed('finished');
    await assertSucceeds(
      updateDoc(session(HOST), {
        status: 'finished',
        [`results.${HOST}`]: { seconds: 1800, km: 5, kcal: 300 },
      }),
    );
  });

  it('그래도 남의 결과는 못 쓴다', async () => {
    await seed('finished');
    await assertFails(
      updateDoc(session(HOST), {
        [`results.${GUEST}`]: { seconds: 9999, km: 99, kcal: 9999 },
      }),
    );
  });
});

describe('상태를 안 바꾸는 쓰기', () => {
  it('내 준비 항목은 켤 수 있다', async () => {
    await seed('accepted');
    await assertSucceeds(updateDoc(session(GUEST), { [`ready.${GUEST}`]: true }));
  });

  it('상대의 준비 항목은 대신 켤 수 없다', async () => {
    // 열려 있으면 혼자서 두 사람 몫을 켜고 출발시킬 수 있다
    await seed('accepted');
    await assertFails(updateDoc(session(GUEST), { [`ready.${HOST}`]: true }));
  });

  it('hostId는 생성 후 바뀌지 않는다', async () => {
    await seed('accepted');
    await assertFails(updateDoc(session(HOST), { hostId: GUEST }));
  });
});

describe('당사자만 본다', () => {
  it('제3자는 읽을 수 없다', async () => {
    await seed('invited');
    await assertFails(updateDoc(session(OTHER), { status: 'accepted' }));
    await assertFails(
      getDocs(query(collection(as(OTHER), 'sessions'), where('guestId', '==', GUEST))),
    );
  });

  it('내 것으로 좁힌 목록은 읽힌다', async () => {
    await seed('invited');
    await assertSucceeds(
      getDocs(
        query(
          collection(as(GUEST), 'sessions'),
          where('guestId', '==', GUEST),
          where('status', 'in', ['invited', 'accepted']),
        ),
      ),
    );
  });

  it('안 좁힌 목록은 거부된다 — 남의 세션이 새지 않게', async () => {
    await seed('invited');
    await assertFails(getDocs(query(collection(as(GUEST), 'sessions'))));
  });
});
