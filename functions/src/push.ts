import * as admin from 'firebase-admin';
import { logger } from 'firebase-functions/v2';

const db = admin.firestore();

/** 알림 탭 시 앱이 어디로 갈지 결정하는 종류 */
export type PushType = 'friendRequest' | 'friendAccepted' | 'runRequest';

interface SendOptions {
  /**
   * "지금 같이 달리자" 같이 시간이 지나면 의미가 없어지는 알림.
   * iOS의 집중 모드를 뚫고 즉시 표시됨 (Time Sensitive Notifications
   * entitlement가 있어야 실제로 적용되고, 없으면 일반 알림으로 처리됨)
   */
  timeSensitive?: boolean;
}

/**
 * 한 사용자의 모든 기기로 알림을 보냄.
 *
 * 토큰은 users/{uid}.fcmTokens 배열에 쌓이는데, 앱 삭제·재설치·장기 미사용으로
 * 죽은 토큰이 남는다. FCM이 "이 토큰은 이제 없음"이라고 알려주면 그 자리에서
 * 지워줘야 배열이 무한히 자라지 않는다.
 */
export async function sendToUser(
  uid: string,
  title: string,
  body: string,
  type: PushType,
  data: Record<string, string> = {},
  options: SendOptions = {},
): Promise<void> {
  const snap = await db.collection('users').doc(uid).get();
  const tokens: string[] = snap.get('fcmTokens') ?? [];
  if (tokens.length === 0) {
    logger.info(`푸시 건너뜀 — 등록된 기기 없음 (uid=${uid}, type=${type})`);
    return;
  }

  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: { type, ...data },
    apns: {
      headers: {
        'apns-push-type': 'alert',
        // 러닝 요청은 즉시, 나머지는 배터리를 아껴 전달
        'apns-priority': options.timeSensitive ? '10' : '5',
      },
      payload: {
        aps: {
          sound: 'default',
          'thread-id': type,
          ...(options.timeSensitive
            ? { 'interruption-level': 'time-sensitive' }
            : {}),
        },
      },
    },
  });

  const dead: string[] = [];
  response.responses.forEach((r, i) => {
    const code = r.error?.code;
    if (
      code === 'messaging/registration-token-not-registered' ||
      code === 'messaging/invalid-registration-token' ||
      code === 'messaging/invalid-argument'
    ) {
      dead.push(tokens[i]);
    } else if (r.error) {
      logger.warn(`푸시 전송 실패 (uid=${uid}): ${r.error.message}`);
    }
  });

  if (dead.length > 0) {
    await db
      .collection('users')
      .doc(uid)
      .update({ fcmTokens: admin.firestore.FieldValue.arrayRemove(...dead) });
    logger.info(`죽은 토큰 ${dead.length}개 정리 (uid=${uid})`);
  }

  logger.info(
    `푸시 전송 (uid=${uid}, type=${type}, 성공=${response.successCount}/${tokens.length})`,
  );
}

/** 알림 문구에 쓸 이름. 비어 있으면 "친구"로 대체 */
export async function displayName(uid: string): Promise<string> {
  const snap = await db.collection('users').doc(uid).get();
  const name = (snap.get('name') as string | undefined)?.trim();
  return name && name.length > 0 ? name : '친구';
}
