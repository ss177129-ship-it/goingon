import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'voice_prompt.dart';

/// 쿨다운의 '음성 한 마디' — 녹음하고, 올리고, 그 주소를 러닝에 붙인다.
///
/// **파일은 Storage, 주소만 문서에.** 프로필 사진과 같은 이유다(문서가
/// 스트림으로 흐르는데 거기에 바이너리가 박히면 매 스냅샷마다 따라온다).
///
/// 경로에 uid가 들어간다(`voices/{uid}/{runId}.m4a`). Storage 규칙은
/// Firestore를 못 읽어서 "이 러닝이 내 것인가"를 물을 수 없고, 소유자를
/// 경로에 박아야만 규칙이 판정할 수 있기 때문이다. 남이 이 파일에 닿는
/// 길은 러닝 문서에 실린 다운로드 주소뿐이고, 그 문서는 Firestore 규칙이
/// 지킨다.
class VoiceNoteService {
  VoiceNoteService({AudioRecorder? recorder, FirebaseFirestore? db})
      : _recorder = recorder ?? AudioRecorder(),
        _db = db ?? FirebaseFirestore.instance;

  final AudioRecorder _recorder;
  final FirebaseFirestore _db;

  /// 파형을 그리는 쪽이 구독한다. 200ms는 눈에 움직임으로 보이면서
  /// 20초를 담아도 점이 100개뿐이라 그릴 때 부담이 없는 간격
  Stream<Amplitude> amplitude() =>
      _recorder.onAmplitudeChanged(const Duration(milliseconds: 200));

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// 녹음 시작. 권한이 없으면 **묻고**, 그래도 없으면 false —
  /// 예외로 던지지 않는다. 마이크가 없다고 완주가 실패한 것은 아니다
  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      // aacLc/64kbps 모노 — 20초에 160KB 남짓. 말 한 마디를 알아듣는 데
      // 이보다 더 쓸 이유가 없다
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        numChannels: 1,
      ),
      path: path,
    );
    return true;
  }

  /// 녹음을 멈추고 파일 경로를 돌려준다. 너무 짧으면(1초 미만) 버린다 —
  /// 버튼을 잘못 스친 것이지 한 마디가 아니다
  Future<String?> stop({Duration? elapsed}) async {
    final path = await _recorder.stop();
    if (path == null) return null;
    if (elapsed != null && elapsed < const Duration(seconds: 1)) {
      await _delete(path);
      return null;
    }
    return path;
  }

  Future<void> cancel() async {
    final path = await _recorder.stop();
    if (path != null) await _delete(path);
  }

  Future<void> dispose() => _recorder.dispose();

  /// 올리고 러닝 문서에 주소를 붙인다. 올린 뒤 로컬 파일은 지운다.
  ///
  /// 주소를 붙이는 것까지가 한 동작이다 — 파일만 올라가고 주소가 안 붙으면
  /// 아무도 닿을 수 없는 파일이 Storage에 남는다
  Future<String?> upload({
    required String uid,
    required String runId,
    required String path,
  }) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final ref = FirebaseStorage.instance.ref('voices/$uid/$runId.m4a');
    await ref.putFile(file, SettableMetadata(contentType: 'audio/mp4'));
    final url = await ref.getDownloadURL();
    await _db.collection('runs').doc(runId).update({'storyClipUrl': url});
    await _delete(path);
    return url;
  }

  Future<void> _delete(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // 임시 디렉터리라 못 지워도 iOS가 알아서 비운다
    }
  }

  /// 한 마디의 상한 — 화면이 이 값으로 자동 정지를 건다
  static Duration get maxLength => VoicePrompt.kMaxLength;
}
