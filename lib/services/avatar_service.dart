import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// 프로필 사진 — 사진첩에서 고른 이미지를 Storage `avatars/{uid}.jpg`에 올리고
/// `users/{uid}.photoUrl`에 주소만 저장함.
///
/// 이미지를 Firestore 문서에 직접 넣지 않는 이유: 친구 목록이 실시간 스트림이라
/// 내 문서가 갱신될 때마다 친구 문서를 통째로 다시 읽는데, 거기에 이미지가
/// 박혀 있으면 아바타 데이터가 매번 따라옴.
///
/// 파일 이름이 uid로 고정이라 사진을 바꿔도 항상 같은 자리를 덮어씀 —
/// 옛 파일이 Storage에 쌓이지 않음. 대신 덮어쓸 때마다 다운로드 토큰이 새로
/// 발급돼 주소가 바뀌므로, 업로드 후 photoUrl 갱신을 반드시 함께 해야 함.
class AvatarService {
  final _db = FirebaseFirestore.instance;
  final _picker = ImagePicker();

  Reference _fileOf(String uid) =>
      FirebaseStorage.instance.ref('avatars/$uid.jpg');

  /// 사진첩 열기 → 512px로 줄여 업로드 → photoUrl 갱신. 새 주소를 돌려줌.
  /// 사용자가 고르지 않고 닫으면 null (실패가 아니므로 예외로 다루지 않음).
  ///
  /// `requestFullMetadata: false` — 촬영 위치 같은 EXIF를 읽지 않겠다는 뜻.
  /// iOS는 이 경우 PHPicker만 쓰므로 사진첩 접근 권한 자체를 묻지 않고,
  /// 사용자가 고른 한 장만 앱에 넘어옴(가장 덜 침습적인 경로).
  Future<String?> pickAndUpload(String uid) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    if (picked == null) return null;

    final bytes = await picked.readAsBytes();
    final file = _fileOf(uid);
    await file.putData(
      bytes,
      SettableMetadata(
        contentType: contentTypeOf(picked.name),
        // 주소가 업로드마다 바뀌므로 오래 캐시해도 낡은 사진이 남지 않음
        cacheControl: 'public, max-age=604800',
      ),
    );
    final url = await file.getDownloadURL();
    await _db.collection('users').doc(uid).update({'photoUrl': url});
    return url;
  }

  /// 사진 지우기 — 필드를 먼저 비워 아무도 깨진 이미지를 보지 않게 하고,
  /// 그다음 파일을 지움
  Future<void> remove(String uid) async {
    await _db
        .collection('users')
        .doc(uid)
        .update({'photoUrl': FieldValue.delete()});
    await deleteFile(uid);
  }

  /// 회원탈퇴 때도 쓰임 — 이미 없는 파일을 지우려는 건 실패가 아님
  Future<void> deleteFile(String uid) async {
    try {
      await _fileOf(uid).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }

  /// 확장자는 항상 .jpg로 올리지만 image_picker가 원본에 따라 png를 돌려줄 때가
  /// 있음. 실제 타입을 그대로 붙여야 브라우저·캐시가 제대로 해석하고,
  /// Storage 규칙의 `image/*` 검사도 통과함 — 여기가 틀리면 업로드가 통째로 거부됨
  static String contentTypeOf(String fileName) =>
      fileName.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
}
