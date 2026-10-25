import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../theme/app_theme.dart';

/// 전면 카메라 프리뷰 + ML Kit 관절 인식 + 관절 오버레이.
///
/// 프레임마다 [onPose] 로 인식 결과(사람이 없으면 null)를 넘긴다.
/// 영상은 기기 안에서만 분석하고 저장·전송하지 않는다.
class PoseCamera extends StatefulWidget {
  const PoseCamera({super.key, required this.onPose});

  final void Function(Pose? pose, DateTime at) onPose;

  @override
  State<PoseCamera> createState() => _PoseCameraState();
}

class _PoseCameraState extends State<PoseCamera> with WidgetsBindingObserver {
  CameraController? _controller;
  CameraDescription? _camera;
  final PoseDetector _detector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );
  bool _busy = false;
  Pose? _pose;
  Size? _imageSize;
  InputImageRotation _rotation = InputImageRotation.rotation0deg;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _error = '카메라를 찾을 수 없어요');
        return;
      }
      _camera = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      final c = CameraController(
        _camera!,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.nv21,
      );
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      _controller = c;
      await c.startImageStream(_onImage);
      setState(() {});
    } on CameraException catch (e) {
      debugPrint('[PoseCamera] 카메라 오류: ${e.code} ${e.description}');
      if (mounted) {
        setState(() => _error = e.code == 'CameraAccessDenied'
            ? '카메라 권한이 필요해요\n설정 → PostureCare → 카메라를 켜주세요'
            : '카메라를 열 수 없어요');
      }
    } catch (e) {
      debugPrint('[PoseCamera] 시작 실패: $e');
      if (mounted) setState(() => _error = '카메라를 열 수 없어요');
    }
  }

  Future<void> _onImage(CameraImage image) async {
    if (_busy || _camera == null) return;
    _busy = true;
    try {
      final input = _toInputImage(image);
      if (input == null) return;
      final poses = await _detector.processImage(input);
      if (!mounted) return;
      final pose = poses.isEmpty ? null : poses.first;
      widget.onPose(pose, DateTime.now());
      setState(() {
        _pose = pose;
        _imageSize = input.metadata!.size;
      });
    } catch (e) {
      debugPrint('[PoseCamera] 인식 실패: $e');
    } finally {
      _busy = false;
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    final rotation =
        InputImageRotationValue.fromRawValue(_camera!.sensorOrientation);
    if (rotation == null) return null;
    _rotation = rotation;
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
    if (image.planes.isEmpty) return null;

    final Uint8List bytes;
    if (image.planes.length == 1) {
      bytes = image.planes.first.bytes;
    } else {
      final buf = WriteBuffer();
      for (final p in image.planes) {
        buf.putUint8List(p.bytes);
      }
      bytes = buf.done().buffer.asUint8List();
    }
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _controller = null;
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final c = _controller;
    _controller = null;
    c?.stopImageStream().catchError((_) {});
    c?.dispose();
    _detector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Text(_error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14)),
      );
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    // 세로 화면 기준: 미리보기 비율은 (높이/너비) = aspectRatio.
    const w = 1000.0;
    final h = w * c.value.aspectRatio;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(c),
              if (_pose != null && _imageSize != null)
                CustomPaint(
                  painter: _PosePainter(
                    pose: _pose!,
                    imageSize: _imageSize!,
                    rotation: _rotation,
                    // 전면 카메라 좌우 반전: 아이폰은 ML Kit 이 받는 영상이 이미
                    // 미리보기와 같은 방향이라 뒤집지 않는다 (뒤집으면 좌우가 반대로 찍힘).
                    mirror: !Platform.isIOS &&
                        _camera?.lensDirection == CameraLensDirection.front,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 관절 점·뼈대 그리기. 좌표 변환은 ML Kit 공식 예제(coordinates_translator) 방식.
class _PosePainter extends CustomPainter {
  _PosePainter({
    required this.pose,
    required this.imageSize,
    required this.rotation,
    required this.mirror,
  });

  final Pose pose;
  final Size imageSize;
  final InputImageRotation rotation;
  final bool mirror;

  Offset? _pt(PoseLandmarkType t, Size size) {
    final l = pose.landmarks[t];
    if (l == null || l.likelihood < 0.5) return null;
    final rotated = rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    final iw = Platform.isIOS || !rotated ? imageSize.width : imageSize.height;
    final ih = Platform.isIOS || !rotated ? imageSize.height : imageSize.width;
    var x = l.x * size.width / iw;
    final y = l.y * size.height / ih;
    if (mirror) x = size.width - x;
    return Offset(x, y);
  }

  static const _bones = [
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftEar, PoseLandmarkType.leftEye],
    [PoseLandmarkType.rightEar, PoseLandmarkType.rightEye],
    [PoseLandmarkType.leftEye, PoseLandmarkType.nose],
    [PoseLandmarkType.rightEye, PoseLandmarkType.nose],
  ];

  static const _dots = [
    PoseLandmarkType.nose,
    PoseLandmarkType.leftEar,
    PoseLandmarkType.rightEar,
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.leftElbow,
    PoseLandmarkType.rightElbow,
    PoseLandmarkType.leftWrist,
    PoseLandmarkType.rightWrist,
    PoseLandmarkType.leftHip,
    PoseLandmarkType.rightHip,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final bone = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final dot = Paint()..color = AppColors.primary;
    final ring = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    for (final b in _bones) {
      final a = _pt(b[0], size), c = _pt(b[1], size);
      if (a != null && c != null) canvas.drawLine(a, c, bone);
    }
    for (final t in _dots) {
      final p = _pt(t, size);
      if (p == null) continue;
      canvas.drawCircle(p, 12, dot);
      canvas.drawCircle(p, 12, ring);
    }
  }

  @override
  bool shouldRepaint(_PosePainter old) => true;
}
