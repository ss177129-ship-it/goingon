import * as admin from 'firebase-admin';
import { logger } from 'firebase-functions/v2';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';

import { displayName, sendToUser } from './push';

/**
 * 잠금화면에 본문을 그대로 실을지.
 *
 * 지금은 싣는다 — 알림만 보고 답할지 말지 정할 수 있어야 대화가 빠르다.
 * 다만 러닝 앱은 폰을 팔에 차고 뛰는 물건이라 화면이 남에게 잘 보인다.
 * 끄면 "지수님이 메시지를 보냈어요"만 간다. 스위치 자리를 남겨 둔다
 */
const SHOW_MESSAGE_BODY = true;

/**
 * 메시지 종류마다 **무엇까지 할지**.
 *
 * 셋을 따로 정하는 이유가 전부 다르다:
 *
 * - `invite`는 안 읽음은 세되 푸시는 보내지 않는다. `onRunRequest`가 이미
 *   "지금 같이 달릴까요?"를 time-sensitive로 보내고 있어서, 여기서 또 보내면
 *   한 번의 GO?에 알림이 두 번 뜬다.
 * - `runResult`는 **둘 다** 하지 않는다. 방금 같이 달리고 마무리 화면을 보고
 *   있는 사람에게 "함께 달렸어요" 알림은 소음이고, 둘 다 아는 일에 안 읽음이
 *   붙으면 배지가 영영 1로 남는다(아무도 그 대화를 열 이유가 없으므로).
 * - `inviteResult`는 둘 다 한다. **지금까지 거절에는 알림이 아예 없었다** —
 *   부른 사람은 앱을 열어봐야 답을 알았다. 이게 이번 단계에서 새로 생기는
 *   유일한 알림이다.
 */
const BEHAVIOR: Record<string, { unread: boolean; push: boolean }> = {
  text: { unread: true, push: true },
  invite: { unread: true, push: false },
  inviteResult: { unread: true, push: true },
  runResult: { unread: false, push: false },
  system: { unread: false, push: false },
};

/** 목록 한 줄에 보일 미리보기. 종류마다 다르게 만든다 */
function previewOf(type: string, text: string | undefined): string {
  switch (type) {
    case 'invite':
      return '같이 달리기 제안';
    case 'inviteResult':
      return text && text.length > 0 ? text : '제안에 답했어요';
    case 'runResult':
      return '함께 달렸어요';
    default:
      // 40자를 넘기면 목록에서 어차피 잘린다. 문서에 통째로 들고 있을 이유가 없다.
      // slice가 아니라 코드포인트로 자른다 — slice(0, 40)은 이모지 한 글자를
      // 반으로 갈라 깨진 문자를 목록에 남긴다
      return [...(text ?? '')].slice(0, 40).join('');
  }
}

// ── DM 메시지 (v1.1) ──────────────────────────────────────────────
//
// 트리거 **하나**가 네 가지를 한다:
//   1. 스레드 문서를 만들거나 갱신 (lastAt·lastPreview·lastSenderId)
//   2. 상대의 안 읽음 수를 올린다 (종류에 따라)
//   3. 상대가 알림을 껐으면 푸시를 건너뛴다 (안 읽음은 그대로 센다)
//   4. 푸시 (종류에 따라)
//
// **스레드 문서를 여기서 만드는 것이 설계의 핵심이다.** 클라이언트가 만들면
// 두 사람이 동시에 말을 걸 때 경합이 생기고, 맞팔 게이트를 규칙 두 곳에
// 걸어야 한다. 메시지 쓰기 규칙이 이미 맞팔을 확인했으므로, 여기까지
// 도달한 메시지는 정당하다 — id에서 참가자를 그대로 꺼내 쓰면 된다.
//
// **안 읽음을 클라이언트가 못 올리는 이유**도 같다. 상대 칸을 올릴 수
// 있으면 배지가 조작되고, "내 칸만 쓰기" 규칙과도 정면으로 부딪힌다.
export const onThreadMessage = onDocumentCreated(
  'threads/{threadId}/messages/{messageId}',
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const threadId = event.params.threadId;
    const pair = threadId.split('_');
    if (pair.length !== 2) return;

    const senderId = data.senderId as string;
    const other = pair[0] === senderId ? pair[1] : pair[0];
    // 보낸 사람이 이 쌍에 속하지 않으면 규칙이 이미 막았어야 한다.
    // 여기까지 왔다면 규칙에 구멍이 있다는 뜻이라 아무것도 하지 않는다
    if (!pair.includes(senderId) || other === senderId) {
      logger.warn(`스레드와 보낸 사람이 어긋남 (tid=${threadId}, from=${senderId})`);
      return;
    }

    const db = admin.firestore();
    const ref = db.collection('threads').doc(threadId);

    // 알림 설정은 갱신 **전에** 읽는다. 갱신이 muted를 건드리지는 않지만,
    // 한 번 읽은 값으로 끝까지 가는 편이 읽는 사람에게 분명하다
    const before = await ref.get();
    const muted = before.get(`muted.${other}`) === true;

    // 같은 메시지가 두 번 배달되는 것은 정상이다 — Firestore 트리거는
    // at-least-once다. increment는 멱등하지 않으므로 그대로 두면 안 읽음이
    // 2가 되고 푸시가 두 번 간다. 방금 처리한 메시지면 조용히 나간다.
    //
    // 완전한 방어는 아니다(두 배달이 동시에 들어오면 둘 다 이 검사를
    // 통과한다). 다만 재배달은 거의 언제나 **처리가 끝난 뒤**에 오고,
    // 남는 오차는 상대가 대화를 열면 markRead가 0으로 지운다
    if (before.get('lastMessageId') === event.params.messageId) {
      logger.info(`같은 메시지 재배달 — 건너뜀 (tid=${threadId})`);
      return;
    }

    const type = (data.type as string) ?? 'text';
    const text = data.text as string | undefined;
    const how = BEHAVIOR[type] ?? BEHAVIOR.text;

    // increment 센티널은 중첩 맵 안에서도 동작하므로 트랜잭션이 필요 없다.
    // merge라서 없던 문서면 만들어지고, 있던 문서면 이 키들만 덮인다
    await ref.set(
      {
        participants: pair,
        ...(before.exists
          ? {}
          : { createdAt: admin.firestore.FieldValue.serverTimestamp() }),
        lastAt: admin.firestore.FieldValue.serverTimestamp(),
        lastPreview: previewOf(type, text),
        lastSenderId: senderId,
        lastMessageId: event.params.messageId,
        ...(how.unread
          ? { unread: { [other]: admin.firestore.FieldValue.increment(1) } }
          : {}),
      },
      { merge: true },
    );

    if (!how.push) return;

    // 알림을 꺼도 안 읽음은 센다 — 껐다는 것은 "지금 울리지 말라"이지
    // "없던 일로 하라"가 아니다
    if (muted) return;

    const name = await displayName(senderId);
    const body =
      type === 'text' && SHOW_MESSAGE_BODY && text
        ? text
        : previewOf(type, text);

    // threadId도 같이 싣지만, 클라이언트의 PushTap은 지금 type·sessionId·
    // fromUid 셋만 읽는다. fromUid만 있으면 threadId는 두 uid를 정렬해
    // 그 자리에서 만들 수 있으므로 라우팅에는 지장이 없다
    await sendToUser(other, name, body, 'message', {
      threadId,
      fromUid: senderId,
    });
  },
);
