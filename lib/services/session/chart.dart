// 채보 — 에피소드를 **데이터**로 둔다.
//
// 왜 코드가 아니라 JSON인가(기술설계서 §3-6): 에피소드가 코드면 콘텐츠 하나를
// 더할 때마다 앱을 다시 심사받아야 한다. 1인팀에게 그건 콘텐츠를 못 늘린다는
// 뜻이고, 콘텐츠가 안 늘면 "매일 열 이유"가 사라진다. 그래서 엔진은 재생기만
// 되고 에피소드는 자산이 된다.
//
// 안전 규칙도 채보 안에 넣는다([ChartSafety]). 스퍼트 길이 같은 것이 코드에
// 있으면 작가가 채보만 고쳐서 위험한 구간을 만들 수 있다 — 안전은 콘텐츠와
// 같은 파일에서 함께 검토되어야 한다.
import 'dart:convert';

/// 세션의 국면. 순서가 곧 이야기이고, 소리·화자·화면이 전부 이것 하나를 본다.
///
/// `chain`이 없는 이유: 다음 에피소드로 잇는 것은 **새 세션의 intro**이지
/// 별도 상태가 아니다. 상태를 늘리면 각 상태의 소리를 새로 상상해야 한다.
enum SessionPhase {
  /// 시작 전
  idle,

  /// 0~1분. 브리지(어제 온 응원)가 재생되는 자리
  intro,

  /// 1~4분. 리듬이 자리를 잡는 구간
  build,

  /// 4~6분. 채보의 동사가 걸리는 구간
  mission,

  /// 6~7.5분. 절정
  climax,

  /// ~8분. 화성 해소 + 도착 벨
  outro,

  /// **잔향 30초 — "발이 결정한다"**(§2-2).
  /// 음악은 낮게 유지된다. 완전히 멈추면 러너스 하이가 끊긴다
  reverb,

  /// 잔향에서 계속 달림 — 이음새 없이 이어진다. 멘트 없음
  freeRun,

  /// 걷기로 바뀜 — 오디오 디브리핑과 음성 채집으로
  cooldown,

  /// 끝
  result;

  /// 러닝이 진행 중인가(일시정지·종료가 아닌가)
  bool get isRunning => switch (this) {
        SessionPhase.idle || SessionPhase.cooldown || SessionPhase.result => false,
        _ => true,
      };

  /// 채보가 구동하는 구간인가. 잔향 이후는 채보가 아니라 발이 구동한다
  bool get isCharted => switch (this) {
        SessionPhase.intro ||
        SessionPhase.build ||
        SessionPhase.mission ||
        SessionPhase.climax ||
        SessionPhase.outro =>
          true,
        _ => false,
      };
}

/// 채보의 동사 — 러너에게 요구하는 행동. **다섯을 넘기지 않는다**(§2-1).
/// 여섯 번째를 넣고 싶어지면 먼저 그 동사의 소리부터 상상해볼 것.
enum ChartVerb {
  /// 리듬 유지
  hold,

  /// 낮은 케이던스로 유지 (터널·오르막 연출)
  holdLow,

  /// 짧게 올린다
  spurt,

  /// 부르면 답한다
  callResponse,

  /// 템포를 바꾼다
  tempoChange;

  static ChartVerb? fromJson(String? s) => switch (s) {
        'hold' => hold,
        'hold_low' => holdLow,
        'spurt' => spurt,
        'call_response' => callResponse,
        'tempo_change' => tempoChange,
        _ => null,
      };
}

/// 채보의 한 구간
class ChartSection {
  const ChartSection({
    required this.at,
    required this.phase,
    this.verb,
    this.narration,
    this.fx,
    this.duration,
  });

  /// 세션 시작으로부터의 시각
  final Duration at;
  final SessionPhase phase;
  final ChartVerb? verb;

  /// 화자 한 줄. **에피소드당 6문장 이내**(§0 원칙 2)이며 [Chart.validate]가 센다
  final String? narration;

  /// 오디오 효과 이름 (예: tunnel_filter, arrival_bell)
  final String? fx;

  /// 동사가 지속되는 길이 (스퍼트 등)
  final Duration? duration;

  static ChartSection fromJson(Map<String, dynamic> m) => ChartSection(
        at: Duration(seconds: (m['t'] as num).round()),
        phase: _phase(m['phase'] as String?),
        verb: ChartVerb.fromJson(m['verb'] as String?),
        narration: m['narration'] as String?,
        fx: m['fx'] as String?,
        duration: m['durationSec'] == null
            ? null
            : Duration(seconds: (m['durationSec'] as num).round()),
      );

  static SessionPhase _phase(String? s) => switch (s) {
        'intro' => SessionPhase.intro,
        'build' => SessionPhase.build,
        'mission' => SessionPhase.mission,
        'climax' => SessionPhase.climax,
        'outro' => SessionPhase.outro,
        _ => throw FormatException('채보에 모르는 phase: $s'),
      };
}

/// 안전 규칙 — 채보와 같은 파일에 산다
class ChartSafety {
  const ChartSafety({this.maxSpurt = const Duration(seconds: 30), this.noStopCues = true});

  /// 스퍼트 상한. 이보다 긴 전력 질주를 요구하는 채보는 실을 수 없다
  final Duration maxSpurt;

  /// **"멈추세요"를 지시하지 않는다.** 달리는 중에 급정지를 요구하면
  /// 뒤에 오는 사람과 부딪힌다. 속도를 줄이는 것은 러너가 알아서 한다
  final bool noStopCues;

  static ChartSafety fromJson(Map<String, dynamic>? m) => ChartSafety(
        maxSpurt: Duration(seconds: ((m?['maxSpurtSec'] as num?) ?? 30).round()),
        noStopCues: (m?['noStopCues'] as bool?) ?? true,
      );
}

/// 에피소드 하나
class Chart {
  const Chart({
    required this.id,
    required this.title,
    required this.duration,
    required this.baseBpm,
    required this.stems,
    required this.sections,
    required this.safety,
  });

  final String id;
  final String title;
  final Duration duration;

  /// 스템의 기준 BPM. 실제 재생 속도는 케이던스가 정한다(§1-1)
  final double baseBpm;

  /// 레이어 이름 → 에셋 파일명 (drums / bass / harmony)
  final Map<String, String> stems;

  /// [at] 오름차순
  final List<ChartSection> sections;
  final ChartSafety safety;

  /// 화자 발화 수 — §0 원칙 2의 상한(6문장)을 세기 위한 것
  int get narrationCount => sections.where((s) => s.narration != null).length;

  static Chart parse(String jsonText) {
    final m = json.decode(jsonText) as Map<String, dynamic>;
    final sections = (m['sections'] as List)
        .map((e) => ChartSection.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    final chart = Chart(
      id: m['id'] as String,
      title: m['title'] as String,
      duration: Duration(seconds: (m['durationSec'] as num).round()),
      baseBpm: (m['baseBPM'] as num).toDouble(),
      stems: Map<String, String>.from(m['stems'] as Map),
      sections: sections,
      safety: ChartSafety.fromJson(
          (m['safety'] as Map?)?.cast<String, dynamic>()),
    );
    chart.validate();
    return chart;
  }

  /// 실을 수 없는 채보를 **로딩 시점에** 거른다. 러닝 중에 발견하면 이미 늦다.
  void validate() {
    if (sections.isEmpty) {
      throw const FormatException('채보에 구간이 하나도 없다');
    }
    if (sections.first.at != Duration.zero) {
      throw const FormatException('채보는 0초에서 시작해야 한다');
    }
    if (sections.last.at >= duration) {
      throw FormatException(
          '마지막 구간(${sections.last.at.inSeconds}s)이 길이(${duration.inSeconds}s) 밖이다');
    }
    if (narrationCount > 6) {
      // §0 원칙 2 — 사운드 총량 상한. 이걸 넘기면 러닝앱이 아니라
      // 러닝을 구실로 한 오디오북이 된다
      throw FormatException('화자 발화가 $narrationCount문장 — 상한은 6문장');
    }
    for (final s in sections) {
      if (s.verb == ChartVerb.spurt) {
        final d = s.duration;
        if (d == null || d > safety.maxSpurt) {
          throw FormatException(
              '스퍼트 길이가 없거나 상한(${safety.maxSpurt.inSeconds}s)을 넘는다');
        }
      }
    }
  }

  /// [elapsed] 시점에 유효한 구간. 채보가 끝난 뒤면 null
  ChartSection? sectionAt(Duration elapsed) {
    if (elapsed >= duration) return null;
    ChartSection? found;
    for (final s in sections) {
      if (s.at <= elapsed) {
        found = s;
      } else {
        break;
      }
    }
    return found;
  }
}
