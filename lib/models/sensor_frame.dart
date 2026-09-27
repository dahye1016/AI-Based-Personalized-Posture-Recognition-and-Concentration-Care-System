/// BLE 로 수신·파싱한 방석 압력 프레임 1개.
///
/// ★ 원시값은 서버로 보내지 않는다. 이 객체는 앱 내부(온디바이스 판정)로만 흐른다.
/// BleService 는 수신·파싱까지만 책임지고 이 타입으로 Stream 에 흘려보낸다.
class SensorFrame {
  final int frameNo; // uint16 프레임 번호 (패킷 유실 감지용)
  final List<int> channels; // ch0~31 압력값 (32개)
  final DateTime receivedAt; // 수신 시각

  const SensorFrame({
    required this.frameNo,
    required this.channels,
    required this.receivedAt,
  });
}
