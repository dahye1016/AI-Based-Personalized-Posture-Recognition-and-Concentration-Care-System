# 방석센서 BLE 연동 테스트 안내 (feat/aro)

작성 2026-08-16

`SensorSource` 추상화에 비어 있던 `BleSensorSource` 를 실제 구현으로 채웠다.
이제 앱이 실기기에서 방석(Cushion-MDEX)에 직접 붙어 32채널 압력을 받는다.

## 바뀐 것

| 파일 | 내용 |
|---|---|
| `lib/services/ble_sensor_source.dart` | **신규.** 스캔 → 연결 → MTU 협상 → Notify 구독 → 66byte 파싱 → 32채널 `List<int>` 방출. 자동 재연결(2→4→…→30초 backoff) 포함 |
| `lib/services/sensor_source.dart` | 빈 껍데기였던 `BleSensorSource` 제거 (위 파일로 이동). `SensorSource`·`MockSensorSource` 는 그대로 |
| `lib/main.dart` | 앱 시작 시 BLE 소스를 만들어 `HomeScreen(source:)` 로 주입 |
| `pubspec.yaml` | `flutter_blue_plus: ^2.3.8`, `permission_handler: ^11.3.1` 추가 |
| `android/app/src/main/AndroidManifest.xml` | `BLUETOOTH_SCAN`·`BLUETOOTH_CONNECT` + Android 11 이하 하위호환 권한 |
| `ios/Runner/Info.plist` | `NSBluetoothAlwaysUsageDescription` |

기존 화면 코드는 **한 줄도 안 건드렸다.** `PostureClassifier` 가 그대로 판정한다.

## 펌웨어 스펙 (맞는지 먼저 확인)

```
기기명   Cushion-MDEX
Service  180A
TX char  2A98  (Notify, 10Hz)
페이로드 66 byte = frame_no(uint16 LE) + ch0~31 (각 uint16 LE)
필요 MTU 69 이상 (66 + ATT 헤더 3)
```

이 중 하나라도 다르면 `lib/services/ble_sensor_source.dart` 상단 상수만 고치면 된다.

## 실행

```bash
flutter pub get
flutter run                              # BLE 사용 (기본)
flutter run --dart-define=USE_BLE=false  # 센서 없이 mock 으로
```

**반드시 실기기에서 실행할 것.** 에뮬레이터·시뮬레이터는 BLE가 안 된다.

iOS는 `ios/` 에서 `pod install` 이 한 번 필요할 수 있다.

## 로그 읽는 법

`flutter run` 콘솔에 `[BLE]` 태그로 전부 찍힌다.

```
[BLE] connect() 시작
[BLE] 스캔 시작
[BLE] 발견 id=XX:XX:… name="Cushion-MDEX" services=[180a] rssi=-52
[BLE] 대상 매칭 … → 연결 시도
[BLE] 연결됨 (GATT connected)
[BLE] MTU=517
[BLE] Notify 구독 시작: 180A/2A98
[BLE] 준비 완료 — 프레임 수신 대기
```

### 증상별 확인

| 로그 | 원인 | 조치 |
|---|---|---|
| `스캔 타임아웃 — 대상 기기 못 찾음` | 방석 전원/광고 문제, 또는 이름·UUID 불일치 | 위 `발견 id=…` 목록에서 방석으로 보이는 항목의 name·services 확인 → 상수 수정 |
| `⚠️ MTU 22 < 69` | MTU 협상 실패 | 66byte가 잘려 파싱이 안 된다. 안드로이드면 재연결, iOS면 기기 재부팅 |
| `프레임 길이 이상: 20 (기대 66)` | 펌웨어 페이로드 길이가 다름 | 펌웨어 스펙 재확인 후 `_payloadLen` 수정 |
| `프레임 유실 N개` | 전파/처리 지연 | 소량이면 정상. 계속 크면 전송 주기를 낮춘다 |
| `대상 characteristic(2A98) 미발견` | UUID 불일치 | nRF Connect 등으로 실제 UUID 확인 |

### 권한

- **Android 12 이상**: 앱 첫 실행 시 블루투스 권한 팝업이 뜬다. 거부하면 스캔이 조용히 실패한다. 설정 → 앱 → 권한에서 다시 허용.
- **Android 11 이하**: 위치 권한이 있어야 BLE 스캔이 된다(매니페스트에 `maxSdkVersion="30"` 으로 넣어둠).
- **iOS**: 첫 실행 시 시스템 팝업. 거부하면 설정 → 앱에서 다시 켜야 한다.

## 아직 안 된 것

- **연결 상태가 화면에 안 보인다.** `BleSensorSource.linkState` 스트림(`연결됨` / `방석 찾는 중…` 등)을 만들어 뒀지만 UI에 안 붙였다. 홈 화면 상단에 배지로 붙이면 바로 쓸 수 있다.
- **`HomeScreen` 과 `RootNav` 가 둘 다 `source.dispose()` 를 부른다.** `StreamController.close()` 는 두 번 불러도 안전해서 지금은 문제없지만, 소유권을 한쪽으로 정리하는 게 맞다.
- **정자세 캘리브레이션 화면은 이 패치에 없다.** 별도로 만든 3화면(측정 안내/측정 중/완료)은 `dev` 브랜치 구조 기준이라 이 브랜치에 그대로 안 붙는다. 필요하면 `SensorSource` 기준으로 다시 맞춰야 한다.
- **`flutter analyze` 미실행.** 작업 환경(리눅스 컨테이너)에서 Dart SDK 다운로드가 네트워크 정책에 막혔다. 받으신 뒤 한 번 돌려주시길.
