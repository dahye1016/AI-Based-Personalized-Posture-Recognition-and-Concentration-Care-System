import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:http/http.dart' as http; // 서버 연동을 위해 추가

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pose & Chair Integrated Monitor',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue), useMaterial3: true),
      home: const PoseDetectorView(),
    );
  }
}

class PoseDetectorView extends StatefulWidget {
  const PoseDetectorView({super.key});

  @override
  State<PoseDetectorView> createState() => _PoseDetectorViewState();
}

class _PoseDetectorViewState extends State<PoseDetectorView> {
  late CameraController _cameraController;
  final PoseDetector _poseDetector = PoseDetector(options: PoseDetectorOptions());
  bool _isDetecting = false;
  List<Pose> _poses = [];

  // --- 의자 서버 연동을 위한 신규 추가 변수 파트 ---
  String _rulePosture = "로딩 중...";
  String _cnnPosture = "로딩 중...";
  String _feedbackMessage = "서버 연결 대기 중...";
  List<dynamic> _sensorValues = [0, 0, 0, 0, 0, 0];
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _startFetchTimer(); // 1초 간격 서버 데이터 갱신 타이머 가동
  }

  Future<void> _initCamera() async {
    _cameraController = CameraController(cameras[0], ResolutionPreset.medium);
    await _cameraController.initialize();
    if (!mounted) return;
    setState(() {});

    _cameraController.startImageStream((CameraImage image) async {
      if (_isDetecting) return;
      _isDetecting = true;

      // [보존]기존의 ML Kit 포즈 디텍션 입력 처리 로직 원형 유지
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final imageInput = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.rotation270deg, 
          format: InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      try {
        final poses = await _poseDetector.processImage(imageInput);
        if (mounted) {
          setState(() {
            _poses = poses;
          });
        }
      } catch (e) {
        debugPrint("ML Kit Error: $e");
      } finally {
        _isDetecting = false;
      }
    });
  }

  // --- [통합 기능] FastAPI 서버로부터 실시간 의자 정보 폴링 ---
  void _startFetchTimer() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        final response = await http.get(Uri.parse("http://127.0.0.1:8000/current-posture"));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          setState(() {
            _rulePosture = data["rule_posture"] ?? "미확인";
            _cnnPosture = data["cnn_posture"] ?? "미확인";
            _feedbackMessage = data["feedback"] ?? "";
            _sensorValues = data["sensors"] ?? [0,0,0,0,0,0];
          });
        }
      } catch (e) {
        setState(() {
          _rulePosture = "연결 끊김";
          _cnnPosture = "연결 끊김";
        });
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _cameraController.dispose();
    _poseDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_cameraController.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("실시간 맞춤형 자세 & 집중도 케어 시스템")),
      body: Column(
        children: [
          // 1. 상단 파트: 기존 카메라 스케줄 영역 보존
          Expanded(
            flex: 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_cameraController),
                if (_poses.isNotEmpty)
                  CustomPaint(
                    painter: PosePainter(_poses, _cameraController.value.previewSize!, InputImageRotation.rotation270deg),
                  ),
              ],
            ),
          ),
          
          // 2. 하단 파트: 새로 합쳐진 스마트 의자 압력 센서 및 실시간 딥러닝 스태터스 보드 UI
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(16.0),
              color: Colors.grey[100],
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Card(
                            color: Colors.blue[50],
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                children: [
                                  const Text("규칙 기반 결과", style: TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(_rulePosture, style: const TextStyle(fontSize: 16, color: Colors.blueAccent)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Card(
                            color: Colors.purple[50],
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                children: [
                                  const Text("1D-CNN 예측결과", style: TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(_cnnPosture, style: const TextStyle(fontSize: 15, color: Colors.purpleAccent, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            const Icon(Icons.feedback, color: Colors.orange),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("실시간 맞춤형 코칭 가이드", style: TextStyle(fontSize: 12, color: Colors.grey)),
                                  Text(_feedbackMessage, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "실시간 모니터링 수치: ${_sensorValues.toString()}",
                      style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'monospace'),
                    )
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// [보존] 다혜님이 기존에 제공한 캔버스 선 그리기 CustomPainter 로직 100% 동일
// =====================================================================
class PosePainter extends CustomPainter {
  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;

  PosePainter(this.poses, this.imageSize, this.rotation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.green;

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.red
      ..strokeWidth = 3.0;

    for (final pose in poses) {
      pose.landmarks.forEach((_, landmark) {
        canvas.drawCircle(
          Offset(landmark.x * size.width / imageSize.height, landmark.y * size.height / imageSize.width),
          5.0,
          paint,
        );
      });

      void drawLine(PoseLandmarkType a, PoseLandmarkType b) {
        final pointA = pose.landmarks[a];
        final pointB = pose.landmarks[b];
        if (pointA == null || pointB == null) return;
        canvas.drawLine(
          Offset(pointA.x * size.width / imageSize.height, pointA.y * size.height / imageSize.width),
          Offset(pointB.x * size.width / imageSize.height, pointB.y * size.height / imageSize.width),
          linePaint,
        );
      }

      drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder);
      drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip);
      drawLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip);
      drawLine(PoseLandmarkType.leftHip, PoseLandmarkType.rightHip);
      drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow);
      drawLine(PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist);
      drawLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow);
      drawLine(PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist);
      drawLine(PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee);
      drawLine(PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle);
      drawLine(PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee);
      drawLine(PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
