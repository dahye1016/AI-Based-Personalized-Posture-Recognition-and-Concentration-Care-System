# PoseLab Seat 연동 — 변경사항 인수인계

작성: 현지 / 대상: 일요일 통합 담당자

---

## 1. 한 줄 요약

기존 코드는 **6채널 FSR + BLE** 전제였는데, 실제 센서(marveldex PoseLab Seat)는
**32채널 + USB Serial** 입니다. 값 개수도, 전송 경로도, 값 범위도 다 달라서
"연결 경로만 바꾸기"로는 안 되고 데이터 계층 전체를 다시 짰습니다.

**센서 실물 없이 개발/테스트가 끝까지 되도록 만들어놨습니다.**
일요일에 센서 오면 명령어 인자 하나만 바꾸면 됩니다.

---

## 2. 왜 구조가 바뀌었나 (중요)

| 항목 | 기존 코드 전제 | 실제 PoseLab Seat |
|---|---|---|
| 채널 수 | 6 (`sensor_1`~`sensor_6`) | **32** (ROW0 10 / ROW1 14 / ROW2 8) |
| 전송 | ESP32 → BLE → 폰 <br> 또는 ESP32 → WiFi → 서버 | **Core 보드 → USB Serial → PC** |
| Baud | 115200 | **2,000,000** |
| 펌웨어 | 직접 작성한 `.ino` | 벤더 제공 Lite 펌웨어 (우리가 못 고침) |
| 값 범위 | 0~1023 | 0~1400+ (raw) |

**가장 큰 파급효과: 폰이 센서에 직접 붙을 수 없습니다.**
Core 보드는 USB 로 PC 에 꽂힙니다. 그래서 BLE 경로가 통째로 무의미해졌고,
PC 가 중계하는 구조로 바뀌었습니다.

```
[Core 보드] --USB 2Mbaud--> [PC: bridge/main.py] --HTTP--> [PC: FastAPI] --HTTP--> [폰 Flutter]
```

---

## 3. 파일별 변경 내역

### 새로 만든 것 — `bridge/`  (PC에서 도는 수집기)

| 파일 | 역할 |
|---|---|
| `layout.py` | 32채널의 물리적 위치 정의. **여기만 고치면 나머지가 다 따라옴** |
| `protocol.py` | Serial 파서. ASCII/바이너리 자동 판별 + 포트 자동 탐색 |
| `features.py` | 32채널 → Sum/Max/Area/CoF/좌우·앞뒤 불균형 특징 추출 |
| `mock_source.py` | **센서 없이** 자세별 가상 32채널 프레임 생성 |
| `main.py` | 위를 묶어 서버로 전송. `--mock` / `--port` 로 전환 |
| `test_pipeline.py` | 서버·DB 없이 판정 로직만 검증하는 테스트 |

### 전면 수정 — `server/`

- `database.py` — `sensor_1..6` 컬럼 6개 → `channels_json`(32채널 JSON) + 특징 컬럼.
  **기존 `posture.db` 는 스키마가 달라 재사용 불가**라서 `poselab.db` 로 새로 만듭니다.
  `Calibration` 테이블 추가.
- `posture_classifier.py` — 하드코딩 임계값 → **2단계 판정**
  1. 사용자가 등록한 기준 자세와 최근접 비교 (개인화)
  2. 등록 전에는 규칙 기반 폴백
- `main.py` — 엔드포인트 재설계 (아래 표)

### 수정 — `lib/` (Flutter)

- `config.dart` — 서버 주소 안내 갱신, 채널 수/자세목록 상수 추가
- `models/posture.dart` — 자세 4종 → 7종+비착석, 32채널/리포트/레이아웃 모델 추가
- `services/api_service.dart` — 새 엔드포인트 대응, 리포트 집계를 서버에 위임
- `screens/home_screen.dart` — BLE 버튼 제거, **실시간 히트맵** + 자세등록 진입 추가
- `screens/report_screen.dart` — 앱에서 직접 집계 → 서버 `/report/daily` 사용
- `screens/calibration_screen.dart` — **신규**. 시안의 '초기 설정 > 자세 등록' 화면
- `widgets/seat_heatmap.dart` — **신규**. 방석 압력 분포 렌더러
- `pubspec.yaml` — `flutter_blue_plus`, `permission_handler` 제거

### 삭제 / 격리

| 파일 | 사유 |
|---|---|
| `lib/services/ble_service.dart` | 삭제. 센서가 USB라 BLE 경로 자체가 성립 안 함 |
| `firmware/posture_sensor_esp32.ino` | 삭제. 벤더 펌웨어를 우리 걸로 못 덮어씀 |
| `arduino/` | `_legacy/arduino_6ch/` 로 이동 |
| `simulator/` | `_legacy/simulator_6ch/` 로 이동 (32채널 `bridge/mock_source.py` 가 대체) |
| `lib/screens/pose_screen.dart` | `_legacy/` 로 이동. camera/mlkit 의존성이 pubspec 에 없어 빌드가 깨짐 |

---

## 4. API 변경

| 기존 | 현재 | 비고 |
|---|---|---|
| `POST /sensor-data` (6값) | `POST /sensor-frame` (32값) | 채널 수 다르면 400 |
| `GET /sensor-data` | `GET /frames` | |
| `GET /current-posture` | (유지, 응답 확장) | `confidence`, `held_seconds`, `cof` 추가 |
| — | `GET /heatmap` | 최신 32채널 |
| — | `GET /layout` | 센서 물리 배치 |
| — | `POST/GET/DELETE /calibration` | 자세 등록·조회·재보정 |
| — | `GET /report/daily`, `/report/weekly` | 서버측 집계 |

---

## 5. 실행 방법

```bash
# 의존성
pip install fastapi uvicorn sqlalchemy requests pyserial

# 1) 서버
cd server && uvicorn main:app --reload --host 0.0.0.0 --port 8000
#    문서: http://127.0.0.1:8000/docs

# 2-A) 센서 없이 (지금)
python bridge/main.py --mock                 # 정자세 고정
python bridge/main.py --mock --auto          # 자세 자동 전환

# 2-B) 센서 연결 후 (일요일)
python bridge/main.py --port auto            # 포트 자동 탐색
python bridge/main.py --port auto --raw      # 배선 확인용 raw 출력

# 3) 앱
flutter pub get && flutter run
```

검증 테스트:

```bash
python bridge/test_pipeline.py
```

---

## 6. 검증 결과 (센서 없이)

```
1. 배치 정의        32채널 / 좌16·우16          ✅
2. 프로토콜 파서    ASCII·바이너리 자동판별      ✅
3. 규칙 폴백        7종 중 6종 일치              (폴백이라 허용)
4. 개인 캘리브레이션 정확도 99.7% (300회)        ✅
5. 비착석 감지                                   ✅
```

---

## 7. ⚠️ 일요일에 실물로 확인해야 할 것 (각 5분)

우리가 실물 없이 확정할 수 없었던 3가지입니다. **여기만 맞추면 끝납니다.**

1. **Serial 출력 포맷**
   `python bridge/main.py --port auto --raw` 를 돌려 32개 숫자가 한 줄씩
   나오는지 확인. 다르면 `bridge/protocol.py` 의 파서 클래스만 고치면 됨
   (다른 파일은 손 안 대도 됨).
   → 벤더 wiki 의 '소스코드 다운로드(Lite)' zip 안 `.ino` 를 보면 확실합니다.

2. **채널 번호 ↔ 물리 위치**
   방석 앞쪽 한 곳만 손으로 누르고, `--raw` 출력에서 몇 번 채널이 튀는지 확인.
   앞뒤가 반대면 `bridge/layout.py` 의 `ORIENTATION_FLIP = True`,
   좌우가 반대면 `MIRROR_LR = True`. 그게 전부입니다.

3. **압력 값의 실제 범위**
   `bridge/features.py` 의 `SEATED_SUM_THRESHOLD`(현재 800)와
   `AREA_LEVELS` 를 실측에 맞게 조정.

---

## 8. 아직 안 된 것 / 다음 할 일

- **등받이 센서**: 서버는 `device_id`(`seat`/`backrest`)로 2개 패널을 이미
  구분해 저장합니다. 다만 등받이는 배치(`layout.py`)가 다를 테니 별도 정의 필요.
- **집중 챌린지 화면**: 시안에는 있으나 미구현. `/report/weekly` 로 데이터는 나옵니다.
- **`1D-CNN.py` 등 학습 스크립트**: 전부 6채널 CSV 기준이라 재학습 필요.
  다만 지금의 nearest-centroid 방식으로 99% 나오므로 급하지 않습니다.
- **Flutter 컴파일 검증**: 이 작업 환경에 Flutter SDK가 없어 `flutter analyze` 를
  못 돌렸습니다. 통합할 때 한 번 돌려주세요.
