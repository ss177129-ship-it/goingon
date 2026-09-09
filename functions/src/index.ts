import * as admin from 'firebase-admin';
import { logger, setGlobalOptions } from 'firebase-functions/v2';
import {
  onDocumentCreated,
  onDocumentDeleted,
} from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';

admin.initializeApp();

import { displayName, sendToUser } from './push';

/**
 * Firestore가 nam5(미국 다중 리전)에 있어서 Firestore 트리거는 미국 리전에
 * 있어야 함 — us-central1이 nam5에 대응함.
 *
 * maxInstances는 폭주 방지용 상한. 무료 한도(월 200만 호출) 대비 실사용은
 * 수천 건 수준이라 10이면 충분하고, 혹시 무한 루프가 생겨도 청구서가
 * 터지지 않게 막아준다.
 */
setGlobalOptions({ region: 'us-central1', maxInstances: 10 });

const db = admin.firestore();

// ── 친구 요청 ──────────────────────────────────────────────────────────

/**
 * 친구 요청이 오면 받는 사람에게 알림.
 *
 * 요청·수락 모델에서는 상대가 앱을 켤 때까지 요청을 보지 못하므로, 이 알림이
 * 없으면 보낸 사람은 며칠씩 대기하게 됨(우회로도 없음)
 */
export const onFriendRequest = onDocumentCreated(
  'friendRequests/{requestId}',
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const fromUid = data.fromUid as string;
    const toUid = data.toUid as string;

    const name = await displayName(fromUid);
    await sendToUser(
      toUid,
      '함께 달리기 요청',
      `${name}님이 함께 달리고 싶어해요`,
      'friendRequest',
      { fromUid },
    );
  },
);

/**
 * 요청 문서가 사라지면 수락·거절·취소 셋 중 하나인데, 셋 다 삭제라서
 * 구분이 안 됨. 삭제 후 두 사람이 실제로 친구가 됐는지를 보고 판단함 —
 * 친구면 수락, 아니면 거절/취소이므로 아무에게도 알리지 않음
 * (거절 통보는 상처를 주고 재요청을 유발함)
 */
export const onFriendRequestResolved = onDocumentDeleted(
  'friendRequests/{requestId}',
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const fromUid = data.fromUid as string;
    const toUid = data.toUid as string;

    // 수락이면 상대가 나를 following에 넣었고, 거절·취소면 안 넣었다.
    // 요청 문서는 어느 쪽이든 지워지므로 관계 쪽을 봐야 구분이 된다.
    // (P6.5 이전에는 `friends`를 봤다 — 그 필드를 지운 뒤로 이 판정이
    //  항상 거짓이 되어 '연결됐어요' 알림이 영영 안 갔다)
    const accepter = await db.collection('users').doc(toUid).get();
    const following: string[] = accepter.get('following') ?? [];
    if (!following.includes(fromUid)) return; // 거절 또는 취소 — 조용히 끝

    const name = await displayName(toUid);
    await sendToUser(
      fromUid,
      '연결됐어요',
      `${name}님과 이제 함께 달릴 수 있어요`,
      'friendAccepted',
      { withUid: toUid },
    );
  },
);

// ── 러닝 요청 (GO?) ────────────────────────────────────────────────────

/**
 * GO? 요청이 생기면 상대에게 즉시 알림. 지금까지는 상대가 앱을 켜고 있어야만
 * 요청이 도착해서, 로비에서 3분 기다린 뒤 카카오톡으로 따로 찔러야 했음
 */
export const onRunRequest = onDocumentCreated(
  'sessions/{sessionId}',
  async (event) => {
    const data = event.data?.data();
    if (!data || data.status !== 'invited') return;
    const hostId = data.hostId as string;
    const guestId = data.guestId as string;

    const name = await displayName(hostId);
    await sendToUser(
      guestId,
      '지금 같이 달릴까요?',
      `${name}님이 함께 달리자고 해요`,
      'runRequest',
      { sessionId: event.params.sessionId, hostId },
      // 시간이 지나면 의미가 없어지는 알림 — 집중 모드를 뚫고 즉시 표시
      { timeSensitive: true },
    );
  },
);

// ── 고스트런 3막 — 함께 달렸다는 소식 (P4, §3-3) ──────────────────────

/**
 * 누군가 내 지난 러닝의 리듬과 함께 달리면 알려준다.
 *
 * 이 알림이 고스트런을 **루프**로 만든다. 없으면 고스트는 일방적으로 소비되고
 * 끝나서, 리듬을 남긴 사람에게는 아무 일도 일어나지 않는다. 도착한 소식에
 * 원탭으로 응원하면 그 응원이 상대의 다음 러닝 시작에 재생된다(브리지, §5).
 *
 * 문구 규칙(§3-1): 승패·순위·추월 언어를 쓰지 않는다. "함께 달렸어요"이지
 * "당신을 이겼어요"가 아니다. 공명 초는 **둘이 만든 것**이라 자랑이 아니라
 * 안부에 가깝다.
 */
export const onGhostCompanion = onDocumentCreated(
  'runs/{runId}/companions/{companionUid}',
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const ownerUid = data.ghostOwnerUid as string;
    const companionUid = data.companionUid as string;
    if (!ownerUid || ownerUid === companionUid) return;

    // 하루에 같은 사람에게서 오는 소식은 3건까지만 개별 알림 (§3-3 빈도 상한).
    // 넘는 것은 조용히 쌓이고 다이제스트가 가져간다(P7)
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const recent = await db
      .collectionGroup('companions')
      .where('ghostOwnerUid', '==', ownerUid)
      .where('at', '>=', since)
      .get();
    if (recent.size > 3) {
      logger.info(`고스트 알림 묶음 처리 — uid=${ownerUid} 오늘 ${recent.size}건`);
      return;
    }

    const name = await displayName(companionUid);
    const seconds = (data.resonanceSeconds as number) ?? 0;
    const body =
      seconds > 0
        ? `${name}님이 당신의 리듬과 함께 달렸어요 — 시차 공명 ${seconds}초`
        : `${name}님이 당신의 리듬과 함께 달렸어요`;

    await sendToUser(ownerUid, '함께 달렸어요', body, 'ghostCompanion', {
      runId: event.params.runId,
      companionUid,
    });
  },
);

/**
 * 응원이 도착했다 — **예고만 보낸다**(§5-4).
 *
 * 내용(누가 어떤 응원을)을 푸시에 실으면 그 자리에서 소모되고 끝난다.
 * 아껴서 다음 러닝의 출발선에 놓아야 여운이 연료가 되고, 세션이 직선이
 * 아니라 고리가 된다. 그래서 이 알림이 하는 말은 "도착했다"까지다.
 *
 * 문법 규칙(§5-5): 기대감이지 죄책감이 아니다. "안 뛰면 스트릭 잃어요"가
 * 아니라 "기다리고 있어요".
 */
export const onCheer = onDocumentCreated('cheers/{cheerId}', async (event) => {
  const data = event.data?.data();
  if (!data) return;
  const fromUid = data.fromUid as string;
  const toUid = data.toUid as string;
  if (!fromUid || !toUid || fromUid === toUid) return;

  const name = await displayName(fromUid);
  await sendToUser(
    toUid,
    '응원이 도착했어요',
    `${name}님이 응원을 남겼어요. 다음 러닝을 시작할 때 들려드릴게요.`,
    'cheer',
    { cheerId: event.params.cheerId, fromUid },
  );
});

// ── 세션 정리 (예전엔 클라이언트가 억지로 하던 일) ─────────────────────

/**
 * 지금까지 이 정리는 "게스트가 앱을 열었을 때만" 돌았고, 아무도 안 열면
 * 영원히 치워지지 않았음. 24시간 넘게 running인 세션도 클라이언트가 조회할
 * 때마다 판정만 하고 실제 상태는 고치지 못했음. 서버가 제자리를 찾아줌
 */
export const cleanupSessions = onSchedule(
  { schedule: 'every 15 minutes', region: 'us-central1' },
  async () => {
    const now = Date.now();
    const staleRequest = new Date(now - 30 * 60 * 1000); // GO? TTL 30분
    const staleRunning = new Date(now - 24 * 60 * 60 * 1000);

    // 답을 기다리다 시간이 다 된 것만 만료다. 수락까지 갔다가 멈춘 것은
    // 누군가 그만둔 것이므로 여기서 건드리지 않는다 — 보낸 사람에게
    // 보여줄 문장이 다르다("답이 오지 않았어요" vs "그만뒀어요")
    let expired = 0;
    // 'waiting'은 2026-09-09 개편 이전의 이름이다. 앱은 더 이상 그 상태를
    // 모르므로 화면 어디에도 안 나오고, 남겨 두면 영영 지워지지 않는 유령이
    // 된다 — 여기서 함께 거둔다
    for (const status of ['invited', 'waiting']) {
      const snap = await db
        .collection('sessions')
        .where('status', '==', status)
        .where('createdAt', '<', staleRequest)
        .limit(400)
        .get();
      if (snap.empty) continue;
      const batch = db.batch();
      snap.docs.forEach((d) => batch.update(d.ref, { status: 'expired' }));
      await batch.commit();
      expired += snap.size;
    }

    // 수락까지 갔지만 아무도 로비에 들어오지 않은 만남. 이걸 안 거두면
    // 홈 카드가 '준비하러 가요'로 굳어 영영 안 없어진다 — 30분이 지났으면
    // 그 약속은 이미 지나간 것이다
    let abandoned = 0;
    {
      const snap = await db
        .collection('sessions')
        .where('status', '==', 'accepted')
        .where('createdAt', '<', staleRequest)
        .limit(400)
        .get();
      if (!snap.empty) {
        const batch = db.batch();
        snap.docs.forEach((d) => batch.update(d.ref, { status: 'cancelled' }));
        await batch.commit();
        abandoned = snap.size;
      }
    }

    const running = await db
      .collection('sessions')
      .where('status', '==', 'running')
      .where('startedAt', '<', staleRunning)
      .limit(400)
      .get();
    if (!running.empty) {
      const batch = db.batch();
      running.docs.forEach((d) => batch.update(d.ref, { status: 'finished' }));
      await batch.commit();
    }

    logger.info(
      `세션 정리 완료 — 만료 요청 ${expired}건, 버려진 약속 ${abandoned}건, ` +
        `멈춘 러닝 ${running.size}건 종료 처리`,
    );
  },
);
