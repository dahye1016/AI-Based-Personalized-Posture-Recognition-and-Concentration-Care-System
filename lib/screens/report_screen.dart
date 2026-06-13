import 'package:flutter/material.dart';
import '../models/posture.dart';
import '../services/api_service.dart';

/// 집중력 트렌드 리포트 화면.
/// /sensor-data(최근 100건)를 분석해
/// - 집중도 점수(바른자세 비율)
/// - 자세 분포
/// - 시간대별 집중도 추이(꺾은선)
/// 를 보여준다.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, required this.api});
  final ApiService api;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  late Future<List<SensorRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchHistory();
  }

  void _reload() => setState(() => _future = widget.api.fetchHistory());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('집중력 리포트'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<List<SensorRecord>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _Message(
              icon: Icons.wifi_off,
              text: '서버에 연결할 수 없어요.\n${snap.error}',
              onRetry: _reload,
            );
          }
          final records = snap.data ?? [];
          if (records.isEmpty) {
            return _Message(
              icon: Icons.inbox,
              text: '아직 수집된 자세 데이터가 없어요.',
              onRetry: _reload,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: _ReportBody(records: records),
          );
        },
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.records});
  final List<SensorRecord> records;

  @override
  Widget build(BuildContext context) {
    final total = records.length;

    // 자세별 카운트
    final counts = <String, int>{};
    for (final r in records) {
      counts[r.posture] = (counts[r.posture] ?? 0) + 1;
    }
    final goodCount = counts['바른자세'] ?? 0;
    final focusScore = total == 0 ? 0 : (goodCount * 100 / total).round();

    // 서버는 시간 역순(최신 먼저) → 오래된 순으로 뒤집어 추이 계산
    final chrono = records.reversed.toList();
    final trend = _focusTrend(chrono, buckets: 10);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _ScoreCard(score: focusScore, sampleCount: total),
        const SizedBox(height: 24),
        const _SectionTitle('집중도 추이'),
        const SizedBox(height: 12),
        _TrendChart(values: trend),
        const SizedBox(height: 28),
        const _SectionTitle('자세 분포'),
        const SizedBox(height: 12),
        ..._distributionBars(counts, total),
      ],
    );
  }

  /// 구간별 바른자세 비율(0~100)
  List<double> _focusTrend(List<SensorRecord> chrono, {required int buckets}) {
    if (chrono.isEmpty) return [];
    final n = chrono.length;
    final size = (n / buckets).ceil().clamp(1, n);
    final result = <double>[];
    for (var i = 0; i < n; i += size) {
      final slice = chrono.sublist(i, (i + size).clamp(0, n));
      final good = slice.where((r) => r.posture == '바른자세').length;
      result.add(good * 100 / slice.length);
    }
    return result;
  }

  List<Widget> _distributionBars(Map<String, int> counts, int total) {
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) {
      final style = PostureStyle.of(e.key);
      final ratio = total == 0 ? 0.0 : e.value / total;
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(style.icon, size: 18, color: style.color),
                const SizedBox(width: 8),
                Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${(ratio * 100).round()}%  (${e.value})',
                    style: TextStyle(color: Colors.grey.shade700)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 10,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(style.color),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.score, required this.sampleCount});
  final int score;
  final int sampleCount;

  Color get _color {
    if (score >= 70) return const Color(0xFF2E7D32);
    if (score >= 40) return const Color(0xFFE65100);
    return const Color(0xFFC62828);
  }

  String get _grade {
    if (score >= 70) return '집중 양호';
    if (score >= 40) return '주의 필요';
    return '자세 개선 필요';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _color.withOpacity(0.4), width: 2),
      ),
      child: Column(
        children: [
          Text('집중도 점수',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          Text('$score',
              style: TextStyle(
                  fontSize: 64, fontWeight: FontWeight.bold, color: _color)),
          Text(_grade,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600, color: _color)),
          const SizedBox(height: 6),
          Text('최근 $sampleCount건 기준 · 바른자세 비율',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

/// 꺾은선 추이 차트 (CustomPainter, 외부 패키지 없음)
class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.values});
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: values.length < 2
          ? Center(
              child: Text('추이를 그릴 데이터가 부족해요',
                  style: TextStyle(color: Colors.grey.shade500)))
          : CustomPaint(
              size: Size.infinite,
              painter: _LinePainter(values),
            ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.values);
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 28.0; // y축 라벨 공간
    final chart = Rect.fromLTWH(left, 0, size.width - left, size.height - 18);

    final grid = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;
    final textStyle =
        TextStyle(color: Colors.grey.shade600, fontSize: 10);

    // 가로 격자 (0/50/100)
    for (final pct in [0, 50, 100]) {
      final y = chart.bottom - chart.height * (pct / 100);
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
      final tp = TextPainter(
        text: TextSpan(text: '$pct', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    Offset pointAt(int i) {
      final x = chart.left +
          (values.length == 1
              ? 0
              : chart.width * (i / (values.length - 1)));
      final y = chart.bottom - chart.height * (values[i] / 100);
      return Offset(x, y);
    }

    // 영역 채우기
    final fillPath = Path()..moveTo(chart.left, chart.bottom);
    for (var i = 0; i < values.length; i++) {
      fillPath.lineTo(pointAt(i).dx, pointAt(i).dy);
    }
    fillPath
      ..lineTo(chart.right, chart.bottom)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()..color = const Color(0xFF1565C0).withOpacity(0.12),
    );

    // 선
    final linePaint = Paint()
      ..color = const Color(0xFF1565C0)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final line = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(pointAt(i).dx, pointAt(i).dy);
    }
    canvas.drawPath(line, linePaint);

    // 점
    final dot = Paint()..color = const Color(0xFF1565C0);
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(pointAt(i), 3, dot);
    }
  }

  @override
  bool shouldRepaint(_LinePainter oldDelegate) =>
      oldDelegate.values != values;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold));
}

class _Message extends StatelessWidget {
  const _Message(
      {required this.icon, required this.text, required this.onRetry});
  final IconData icon;
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700)),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}
