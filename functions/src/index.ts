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

    const accepter = await db.collection('users').doc(toUid).get();
    const friends: string[] = accepter.get('friends') ?? [];
    if (!friends.includes(fromUid)) return; // 거절 또는 취소 — 조용히 끝

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
    if (!data || data.status !== 'waiting') return;
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

    let cancelled = 0;
    for (const status of ['waiting', 'ready']) {
      const snap = await db
        .collection('sessions')
        .where('status', '==', status)
        .where('createdAt', '<', staleRequest)
        .limit(400)
        .get();
      if (snap.empty) continue;
      const batch = db.batch();
      snap.docs.forEach((d) => batch.update(d.ref, { status: 'cancelled' }));
      await batch.commit();
      cancelled += snap.size;
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
      `세션 정리 완료 — 만료 요청 ${cancelled}건 취소, 멈춘 러닝 ${running.size}건 종료 처리`,
    );
  },
);
