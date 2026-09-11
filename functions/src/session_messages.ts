import * as admin from 'firebase-admin';
import { logger } from 'firebase-functions/v2';
import {
  onDocumentCreated,
  onDocumentUpdated,
} from 'firebase-functions/v2/firestore';

// ── 세션이 대화의 한 줄이 된다 (v1.1 3단계) ────────────────────────
//
// ## 왜 서버가 쓰나
//
// 세션 상태가 바뀌는 경로가 여럿이다 — 수락, 거절, 만료(클라이언트가 감지),
// 취소, 결과 제출, 그리고 15분마다 도는 서버 정리(`cleanupSessions`).
// 양쪽 클라이언트가 각자 "내가 본 변화"를 메시지로 쓰면 **중복되거나
// 빠진다**: 둘 다 본 전이는 두 줄이 되고, 둘 다 앱이 꺼져 있을 때 서버가
// 만료시킨 것은 아무 줄도 안 남는다.
//
// 세션 문서의 변화 자체를 한 곳에서 보면 그 두 실패가 동시에 사라진다.
// 클라이언트는 이제 세션을 만들고 상태를 바꾸기만 하면 되고, 대화에
// 남는 것은 저절로 따라온다.
//
// ## 멱등성
//
// 트리거는 at-least-once다. 그래서 **메시지 id를 세션 상태에서 만든다** —
// `{sessionId}_{status}`. 같은 전이가 두 번 배달돼도 같은 문서를 덮어쓸
// 뿐이라 대화에 같은 줄이 두 번 서지 않는다. `add()`를 쓰면 재배달마다
// 줄이 하나씩 늘어난다.

/** threads/{작은uid_큰uid} — friendRequests·follows와 같은 결정적 id */
function threadIdOf(a: string, b: string): string {
  return a < b ? `${a}_${b}` : `${b}_${a}`;
}

interface Line {
  /** 문서 id. 같은 전이는 같은 id라 재배달이 줄을 늘리지 않는다 */
  id: string;
  type: 'invite' | 'inviteResult' | 'runResult' | 'system';
  /** 보낸 사람 — 안 읽음이 **상대 쪽**으로 올라가야 하므로 정확해야 한다 */
  senderId: string;
  text?: string;
  meta?: Record<string, unknown>;
}

async function postLine(
  sessionId: string,
  hostId: string,
  guestId: string,
  line: Line,
): Promise<void> {
  const db = admin.firestore();
  const tid = threadIdOf(hostId, guestId);
  const ref = db
    .collection('threads')
    .doc(tid)
    .collection('messages')
    .doc(line.id);

  const body = {
    senderId: line.senderId,
    type: line.type,
    sessionId,
    ...(line.text ? { text: line.text } : {}),
    ...(line.meta ? { meta: line.meta } : {}),
  };

  try {
    // **`set`이 아니라 `create`다.** set으로 덮어쓰면 재배달마다 `at`이
    // 지금 시각으로 새로 찍혀, 10분 전의 제안이 그 뒤에 오간 말들 **아래로**
    // 내려간다. onCreate는 다시 안 울리므로 스레드의 lastAt은 안 따라가고,
    // 대화의 시간 순서만 조용히 어긋난다
    await ref.create({
      ...body,
      at: admin.firestore.FieldValue.serverTimestamp(),
    });
    logger.info(`대화에 줄 추가 (tid=${tid}, type=${line.type}, sid=${sessionId})`);
  } catch (e) {
    // 이미 있는 줄 = 재배달이거나, 결과가 나중에 채워진 경우다.
    // 후자는 내용만 갱신하고 시각은 처음 것을 지킨다
    if ((e as { code?: number }).code !== 6 /* ALREADY_EXISTS */) throw e;
    await ref.set(body, { merge: true });
    logger.info(`대화의 줄 갱신 (tid=${tid}, type=${line.type}, sid=${sessionId})`);
  }
}

/** 두 uid를 세션 문서에서 꺼낸다. 하나라도 없으면 쓸 수 없는 문서다 */
function pairOf(data: admin.firestore.DocumentData | undefined):
    { hostId: string; guestId: string } | null {
  const hostId = data?.hostId as string | undefined;
  const guestId = data?.guestId as string | undefined;
  if (!hostId || !guestId || hostId === guestId) return null;
  return { hostId, guestId };
}

// ── GO?가 대화에 선다 ─────────────────────────────────────────────
//
// 푸시는 여기서 보내지 않는다. `onRunRequest`가 이미 "지금 같이 달릴까요?"를
// time-sensitive로 보내고 있고, `onThreadMessage`도 `invite`에는 푸시를
// 걸지 않는다 — 한 번의 GO?에 알림이 두 번 뜨면 안 된다
export const onSessionInvite = onDocumentCreated(
  'sessions/{sessionId}',
  async (event) => {
    const data = event.data?.data();
    if (!data || data.status !== 'invited') return;
    const pair = pairOf(data);
    if (!pair) return;

    await postLine(event.params.sessionId, pair.hostId, pair.guestId, {
      id: `${event.params.sessionId}_invited`,
      type: 'invite',
      senderId: pair.hostId,
      text: '같이 달릴래요?',
    });
  },
);

/** 상태마다 대화에 남길 한 줄. null이면 아무것도 안 남긴다 */
function lineFor(
  sessionId: string,
  status: string,
  after: admin.firestore.DocumentData,
  hostId: string,
  guestId: string,
): Line | null {
  switch (status) {
    case 'accepted':
      // 수락은 **게스트만** 할 수 있다(규칙이 강제한다). 그래서 보낸 사람이
      // 게스트이고, 안 읽음은 기다리던 호스트 쪽으로 올라간다
      return {
        id: `${sessionId}_accepted`,
        type: 'inviteResult',
        senderId: guestId,
        text: '좋아요, 같이 달려요',
      };

    case 'declined': {
      const msg = (after.declineMessage as string | undefined)?.trim();
      return {
        id: `${sessionId}_declined`,
        type: 'inviteResult',
        senderId: guestId,
        // **거절 문구가 곧 메시지다.** 지금까지 이 한 줄은 12시간 창 안에서만
        // 카드에 떠 있다가 사라졌고, "30분 뒤 어때요?"를 받아 줄 자리가
        // 앱 어디에도 없어서 사람이 외워야 했다. 대화에 남으면 답할 수 있다
        text: msg && msg.length > 0 ? msg : '지금은 어려워요',
      };
    }

    // ── 만료와 취소는 `system`이다. 사람이 한 일이 아니기 때문이다 ──
    //
    // `inviteResult`로 두면 둘 다 푸시와 안 읽음이 붙는데, 이 두 상태는
    // **15분마다 도는 `cleanupSessions`가 한 번에 여러 건을 밀어낸다.**
    // 어제 저녁 다섯 명에게 GO?를 보낸 사람은 다음 스윕에서 "답이 오지
    // 않았어요" 푸시를 같은 분에 다섯 번 받는다.
    //
    // 더 나쁜 것은 취소였다. `senderId: hostId`로 고정돼 있어서, 크론이
    // 버려진 약속을 정리한 것도 **호스트 이름으로** "제안을 거뒀어요"라고
    // 상대에게 알렸다 — 하지 않은 일을 한 것처럼 말하는 알림이다.
    //
    // 줄은 남고 알림만 빠진다. 대화를 열면 무슨 일이 있었는지 보인다
    case 'expired':
      return {
        id: `${sessionId}_expired`,
        type: 'system',
        senderId: guestId,
        text: '제안 시간이 지났어요',
      };

    case 'cancelled':
      return {
        id: `${sessionId}_cancelled`,
        type: 'system',
        senderId: hostId,
        text: '제안이 취소됐어요',
      };

    case 'finished': {
      // 결과는 사람마다 다르다. 하나의 줄에 둘 다 싣고 각자 자기 것을 읽는다
      const results = (after.results ?? {}) as Record<string, {
        seconds?: number;
        km?: number;
      }>;
      const packed: Record<string, { seconds: number; km: number }> = {};
      for (const [uid, r] of Object.entries(results)) {
        packed[uid] = {
          seconds: Math.max(0, Math.round(r?.seconds ?? 0)),
          km: Math.max(0, r?.km ?? 0),
        };
      }
      if (Object.keys(packed).length === 0) return null;
      return {
        id: `${sessionId}_finished`,
        type: 'runResult',
        // 둘 다 아는 일이라 안 읽음도 푸시도 붙지 않는다
        // (`onThreadMessage`의 BEHAVIOR 표).
        //
        // **그래도 senderId는 아무나 넣으면 안 된다.** 이 줄이 대화의
        // 맨 아래가 되는데, 클라이언트는 "맨 아래가 내 말이면 읽을 게
        // 없다"고 판단한다 — 호스트로 두면 호스트가 대화를 열어도 읽음
        // 처리가 안 돼서 수락 때 올라간 배지 1이 영영 안 지워진다.
        // 달리기를 마칠 때마다 하나씩 쌓인다
        senderId: guestId,
        meta: { results: packed },
      };
    }

    default:
      // invited는 onSessionInvite가, running은 아무 줄도 남기지 않는다 —
      // 달리기 시작한 것은 곧 결과로 이어지므로 줄이 둘이 될 필요가 없다
      return null;
  }
}

// ── 수락·거절·만료·취소·결과가 같은 줄기에 이어 붙는다 ──────────────
export const onSessionChanged = onDocumentUpdated(
  'sessions/{sessionId}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!after) return;

    const status = after.status as string | undefined;
    if (!status) return;

    // 상태가 바뀔 때만 보면 **결과의 절반을 놓친다.**
    //
    // `results`는 uid마다 따로 채워진다. 먼저 마친 사람이 자기 결과와
    // `status: 'finished'`를 함께 쓰고, 상대는 몇 초 뒤에 자기 결과만
    // 쓴다 — 그 두 번째 쓰기는 상태를 안 바꾸므로 트리거가 아무것도
    // 하지 않고, 대화에 남는 기록은 영원히 한 사람 것뿐이다.
    // 같은 id로 다시 쓰면 덮어쓸 뿐이라(멱등) 줄이 늘지는 않는다
    const statusChanged = status !== before?.status;
    const resultsChanged = status === 'finished' &&
        JSON.stringify(after.results ?? {}) !==
            JSON.stringify(before?.results ?? {});
    if (!statusChanged && !resultsChanged) return;

    const pair = pairOf(after);
    if (!pair) return;

    const line = lineFor(
      event.params.sessionId,
      status,
      after,
      pair.hostId,
      pair.guestId,
    );
    if (!line) return;

    await postLine(event.params.sessionId, pair.hostId, pair.guestId, line);
  },
);
