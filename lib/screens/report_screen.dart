import 'package:flutter/material.dart';
import '../models/posture.dart';
import '../services/api_service.dart';

/// 집중력 트렌드 리포트 화면.
/// 서버 /report/daily 집계를 받아
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
  late Future<DailyReport> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchDailyReport();
  }

  void _reload() => setState(() => _future = widget.api.fetchDailyReport());

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
      body: FutureBuilder<DailyReport>(
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
          final report = snap.data;
          if (report == null || report.distribution.isEmpty) {
            return _Message(
              icon: Icons.inbox,
              text: '아직 수집된 자세 데이터가 없어요.\n'
                  'PC에서 bridge/main.py 가 돌고 있는지 확인해주세요.',
              onRetry: _reload,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: _ReportBody(report: report),
          );
        },
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report});
  final DailyReport report;

  @override
  Widget build(BuildContext context) {
    // 시간대별 '정자세 비율'을 그대로 추이 그래프로 씁니다.
    // (집계는 서버가 이미 해줬으므로 앱은 그리기만 합니다)
    final trend = report.hourly.map((h) => h.goodRatio).toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _ScoreCard(
          score: report.goodRatio.round(),
          sampleCount: report.seatedSeconds ~/ 60,
        ),
        const SizedBox(height: 8),
        Center(
          child: Text('오늘 착석 ${report.seatedLabel}',
              style: TextStyle(color: Colors.grey.shade600)),
        ),
        const SizedBox(height: 24),
        const _SectionTitle('시간대별 집중도'),
        const SizedBox(height: 12),
        _TrendChart(values: trend),
        if (report.hourly.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${report.hourly.first.hour}시',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              Text('${report.hourly.last.hour}시',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ],
          ),
        ],
        const SizedBox(height: 28),
        const _SectionTitle('자세 분포'),
        const SizedBox(height: 12),
        ..._distributionBars(report.distribution),
      ],
    );
  }

  List<Widget> _distributionBars(Map<String, double> dist) {
    final entries = dist.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) {
      final style = PostureStyle.of(e.key);
      final ratio = (e.value / 100).clamp(0.0, 1.0);
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(style.icon, size: 18, color: style.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(e.key,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text('${e.value.toStringAsFixed(1)}%',
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
          Text('오늘 착석 $sampleCount분 기준 · 정자세 비율',
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
