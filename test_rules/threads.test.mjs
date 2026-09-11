// DM 규칙 — threads / messages
//
// 이 격자가 있는 이유: 여기가 새면 **남의 사적인 대화가 새는** 것이다.
// 이 저장소 규칙은 이미 두 번 조용히 샜다 — friends 무단 추가(동의 없는
// 연결), runs visibility(안 좁힌 쿼리가 기본값으로 통과). 둘 다 "되긴 되니까"
// 넘어갔다가 나중에 발견됐다. DM은 그렇게 발견되면 늦다.
//
//   threadId = "작은uid_큰uid"
//
//   읽기 ── 문서가 아니라 **id**로 판정한다 (get() 0회)
//   쓰기 ── 맞팔 두 간선이 살아 있을 때만, 차단당하지 않았을 때만
//   수정 ── 자기 unread/muted 칸만. 나머지는 전부 서버(Admin SDK)
//   삭제 ── 없다. 메시지도 스레드도
//
// 특히 지키는 것 셋:
//   1. 아무 사이도 아닌 사람이 남의 스레드를 목록으로도 단건으로도 못 본다
//   2. 맞팔이 끊기면 과거는 남고 새 메시지만 막힌다
//   3. 상대의 안 읽음 칸을 못 건드린다 (조작 불가)

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
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

const A = 'aaa'; // 사전순으로 앞. threadId의 왼쪽
const B = 'bbb'; // 사전순으로 뒤. threadId의 오른쪽
const C = 'ccc'; // 아무 사이도 아닌 사람

const TID = `${A}_${B}`;
const edge = (from, to) => `${from}_${to}`;

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

beforeEach(async () => {
  await env.clearFirestore();
});

const as = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();

const thread = (uid) => doc(as(uid), 'threads', TID);
const messages = (uid, tid = TID) =>
  collection(as(uid), 'threads', tid, 'messages');

/**
 * A와 B는 맞팔, C는 아무 사이도 아니다. 스레드 하나가 이미 있다
 * (서버가 만든 모양 그대로 — 클라이언트는 스레드를 못 만든다).
 */
async function seed({ mutual = true, blocked = {} } = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', A), { name: 'A', blocked: blocked[A] ?? [] });
    await setDoc(doc(db, 'users', B), { name: 'B', blocked: blocked[B] ?? [] });
    await setDoc(doc(db, 'users', C), { name: 'C' });

    if (mutual) {
      await setDoc(doc(db, 'follows', edge(A, B)), { followerUid: A, followeeUid: B });
      await setDoc(doc(db, 'follows', edge(B, A)), { followerUid: B, followeeUid: A });
    }

    await setDoc(doc(db, 'threads', TID), {
      participants: [A, B],
      createdAt: new Date(),
      lastAt: new Date(),
      lastPreview: '안녕',
      lastSenderId: A,
      unread: { [A]: 0, [B]: 3 },
      muted: { [A]: false, [B]: false },
    });
    await setDoc(doc(db, 'threads', TID, 'messages', 'm1'), {
      senderId: A,
      type: 'text',
      at: new Date(),
      text: '안녕',
    });
  });
}

/** 규칙이 요구하는 모양의 텍스트 메시지 */
const text = (senderId, body) => ({
  senderId,
  type: 'text',
  at: serverTimestamp(),
  text: body,
});

describe('당사자만 본다', () => {
  it('참가자는 스레드를 읽는다', async () => {
    await seed();
    await assertSucceeds(getDoc(thread(A)));
    await assertSucceeds(getDoc(thread(B)));
  });

  it('아무 사이도 아닌 사람은 스레드를 못 읽는다', async () => {
    await seed();
    await assertFails(getDoc(thread(C)));
  });

  it('로그인하지 않으면 못 읽는다', async () => {
    await seed();
    await assertFails(getDoc(doc(anon(), 'threads', TID)));
  });

  it('참가자는 메시지를 읽는다', async () => {
    await seed();
    await assertSucceeds(getDocs(messages(A)));
  });

  it('남의 대화 메시지는 못 읽는다 — 여기가 이 파일의 존재 이유다', async () => {
    await seed();
    await assertFails(getDocs(messages(C)));
  });

  // 아직 말을 나눈 적 없는 상대의 스레드를 열어보는 것은 정상 동작이다.
  // 규칙이 resource.data를 보면 없는 문서에서 평가 에러가 나 권한 거부가
  // 되고, 대화 탭이 통째로 실패한다 — friendRequests에서 겪은 그 함정이다
  it('없는 스레드를 확인하는 것은 거부가 아니라 "없음"이다', async () => {
    await seed();
    const fresh = `${A}_zzz`;
    await assertSucceeds(getDoc(doc(as(A), 'threads', fresh)));
  });
});

describe('목록은 좁혀야 한다', () => {
  it('participants로 좁힌 목록은 통과한다', async () => {
    await seed();
    await assertSucceeds(
      getDocs(
        query(
          collection(as(A), 'threads'),
          where('participants', 'array-contains', A),
        ),
      ),
    );
  });

  // 안 좁힌 쿼리가 통과하면 남의 대화 목록이 통째로 나온다.
  // runs에서 `.get('visibility', 기본값)` 때문에 실제로 샜던 것과 같은 모양
  it('안 좁힌 목록은 거부된다', async () => {
    await seed();
    await assertFails(getDocs(collection(as(A), 'threads')));
  });

  it('남의 uid로 좁힌 목록은 거부된다', async () => {
    await seed();
    await assertFails(
      getDocs(
        query(
          collection(as(C), 'threads'),
          where('participants', 'array-contains', A),
        ),
      ),
    );
  });
});

describe('스레드는 서버가 만든다', () => {
  it('참가자라도 스레드를 못 만든다', async () => {
    await seed();
    await assertFails(
      setDoc(doc(as(A), 'threads', `${A}_zzz`), {
        participants: [A, 'zzz'],
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('스레드는 지울 수 없다 — 한쪽이 지우면 상대의 대화도 사라진다', async () => {
    await seed();
    await assertFails(deleteDoc(thread(A)));
  });
});

describe('id는 정렬된 두 조각이어야 한다', () => {
  // 뒤집힌 id가 통과하면 같은 쌍에 스레드가 둘 생긴다. 목록에 두 줄이 뜨고,
  // 읽음 처리는 정렬된 쪽에만 가므로 뒤집힌 쪽의 배지가 영영 안 지워진다
  it('뒤집힌 id로는 못 쓴다', async () => {
    await seed();
    await assertFails(addDoc(messages(A, `${B}_${A}`), text(A, '뒤집힌 방')));
  });

  // hasAny만으로 판정하면 "a_b_c"도 통과한다 — 아무 데도 안 닿는 고아
  // 메시지를 무한정 쌓을 수 있다
  it('조각이 셋인 id로는 못 쓴다', async () => {
    await seed();
    await assertFails(addDoc(messages(A, `${A}_${B}_${C}`), text(A, '고아')));
  });

  it('뒤집힌 id는 읽지도 못한다', async () => {
    await seed();
    await assertFails(getDoc(doc(as(A), 'threads', `${B}_${A}`)));
  });
});

describe('말은 맞팔일 때만', () => {
  it('맞팔이면 텍스트를 보낼 수 있다', async () => {
    await seed();
    await assertSucceeds(addDoc(messages(A), text(A, '내일 아침 어때')));
  });

  it('한쪽 간선만 남으면 막힌다', async () => {
    await seed();
    await env.withSecurityRulesDisabled(async (ctx) => {
      await deleteDoc(doc(ctx.firestore(), 'follows', edge(B, A)));
    });
    await assertFails(addDoc(messages(A), text(A, '거기 있어?')));
  });

  // 과거는 남고 새 말만 막힌다. 대화를 지우는 것보다 정직하다
  it('관계가 끊겨도 지난 대화는 계속 읽힌다', async () => {
    await seed({ mutual: false });
    await assertSucceeds(getDocs(messages(A)));
    await assertFails(addDoc(messages(A), text(A, '...')));
  });

  it('상대가 나를 차단하면 못 보낸다', async () => {
    await seed({ blocked: { [B]: [A] } });
    await assertFails(addDoc(messages(A), text(A, '왜 답이 없어')));
  });

  it('아무 사이도 아닌 사람은 남의 스레드에 못 쓴다', async () => {
    await seed();
    await assertFails(addDoc(messages(C), text(C, '안녕하세요')));
  });
});

describe('보낸 사람을 속일 수 없다', () => {
  it('상대 이름으로 못 보낸다', async () => {
    await seed();
    await assertFails(addDoc(messages(A), text(B, '내가 한 말 아님')));
  });

  // 시각을 직접 적을 수 있으면 과거로 적어 남의 말 위에 끼워 넣을 수 있다
  it('시각을 직접 적으면 거부된다', async () => {
    await seed();
    await assertFails(
      addDoc(messages(A), { ...text(A, '어제 그랬잖아'), at: new Date(0) }),
    );
  });

  it('빈 본문은 거부된다', async () => {
    await seed();
    await assertFails(addDoc(messages(A), text(A, '')));
  });

  // 상한이 없으면 한 번의 쓰기로 문서 한도(1MiB)를 채울 수 있다
  it('1000자를 넘으면 거부된다', async () => {
    await seed();
    await assertFails(addDoc(messages(A), text(A, 'ㄱ'.repeat(1001))));
  });

  it('모르는 필드가 붙으면 거부된다', async () => {
    await seed();
    await assertFails(
      addDoc(messages(A), { ...text(A, '안녕'), sessionId: 'sess1' }),
    );
  });
});

describe('제안 말풍선은 클라이언트가 못 쓴다', () => {
  // 세션 상태가 바뀌는 경로가 여럿이라(수락·거절·만료·취소·결과) 양쪽
  // 클라이언트가 각자 쓰면 중복되거나 빠진다. 서버만 쓴다
  for (const type of ['invite', 'inviteResult', 'runResult', 'system']) {
    it(`${type} 메시지는 거부된다`, async () => {
      await seed();
      await assertFails(
        addDoc(messages(A), {
          senderId: A,
          type,
          at: serverTimestamp(),
          text: '같이 달리기',
        }),
      );
    });
  }
});

describe('메시지는 불변이다', () => {
  it('보낸 말을 고칠 수 없다', async () => {
    await seed();
    await assertFails(
      updateDoc(doc(as(A), 'threads', TID, 'messages', 'm1'), { text: '딴말' }),
    );
  });

  it('보낸 말을 지울 수 없다', async () => {
    await seed();
    await assertFails(deleteDoc(doc(as(A), 'threads', TID, 'messages', 'm1')));
  });
});

describe('안 읽음은 자기 칸만', () => {
  it('내 칸을 0으로 만들 수 있다', async () => {
    await seed();
    await assertSucceeds(updateDoc(thread(B), { [`unread.${B}`]: 0 }));
  });

  // 여기가 새면 안 읽음 배지가 조작된다
  it('상대 칸은 못 건드린다', async () => {
    await seed();
    await assertFails(updateDoc(thread(A), { [`unread.${B}`]: 0 }));
  });

  it('내 칸을 0이 아닌 값으로 못 만든다', async () => {
    await seed();
    await assertFails(updateDoc(thread(B), { [`unread.${B}`]: 99 }));
  });

  // 클라이언트(ThreadService.markRead)가 어떤 예외를 삼켜야 하는지를 정하는
  // 테스트다. 규칙의 diff(resource.data)가 없는 문서에서 null을 참조해
  // **not-found가 아니라 permission-denied**로 거부된다
  it('없는 스레드에는 읽음 처리를 할 수 없다', async () => {
    await seed();
    await assertFails(
      updateDoc(doc(as(A), 'threads', `${A}_zzz`), { [`unread.${A}`]: 0 }),
    );
  });

  it('내 알림만 끌 수 있다', async () => {
    await seed();
    await assertSucceeds(updateDoc(thread(A), { [`muted.${A}`]: true }));
    await assertFails(updateDoc(thread(A), { [`muted.${B}`]: true }));
  });

  // 값을 안 막으면 자기 칸에 긴 문자열을 넣을 수 있고,
  // 상대는 목록을 열 때마다 그걸 내려받는다
  it('알림 칸에 bool이 아닌 것은 못 넣는다', async () => {
    await seed();
    await assertFails(updateDoc(thread(A), { [`muted.${A}`]: 'ㄱ'.repeat(5000) }));
  });
});

describe('서버의 칸은 서버만', () => {
  for (const [field, value] of [
    ['lastPreview', '조작된 미리보기'],
    ['lastSenderId', 'ccc'],
    ['participants', [A, 'ccc']],
  ]) {
    it(`${field}는 참가자도 못 바꾼다`, async () => {
      await seed();
      await assertFails(updateDoc(thread(A), { [field]: value }));
    });
  }
});

describe('신고는 넣을 수만 있다', () => {
  it('내 이름으로 신고를 넣는다', async () => {
    await seed();
    await assertSucceeds(
      addDoc(collection(as(A), 'reports'), {
        reporterUid: A,
        targetUid: B,
        threadId: TID,
        messageId: 'm1',
        at: serverTimestamp(),
      }),
    );
  });

  it('남의 이름으로는 못 넣는다', async () => {
    await seed();
    await assertFails(
      addDoc(collection(as(A), 'reports'), { reporterUid: B, targetUid: A }),
    );
  });

  it('모르는 필드가 붙은 신고는 거부된다', async () => {
    await seed();
    await assertFails(
      addDoc(collection(as(A), 'reports'), {
        reporterUid: A,
        targetUid: B,
        at: serverTimestamp(),
        payload: 'ㄱ'.repeat(100),
      }),
    );
  });

  // 신고당한 사람이 자기 신고를 볼 수 있으면 보복이 시작된다
  it('신고는 아무도 읽을 수 없다', async () => {
    await seed();
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'reports', 'r1'), {
        reporterUid: A,
        targetUid: B,
      });
    });
    await assertFails(getDoc(doc(as(A), 'reports', 'r1')));
    await assertFails(getDoc(doc(as(B), 'reports', 'r1')));
  });
});
