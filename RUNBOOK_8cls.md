# 8종(0~7, 7=거북목) 64ch 실측 → 학습 → 서버 교체 순서

PowerShell 기준. 모든 명령은 `C:\Users\jungd\posture-64ch` 에서 실행합니다.

## 라벨 (앱 posture_class.dart 순서와 동일, 바꾸지 말 것)
| 값 | 코드 | 영문 | 한글 |
|---|---|---|---|
| 0 | p0 | not_sitting | 앉지 않음 |
| 1 | p1 | sitting_straight | 정자세 |
| 2 | p2 | lean_forward | 앞으로 숙이기 (등받이 값 없음) |
| 3 | p3 | cross_leg_right | 오른다리 꼬기 |
| 4 | p4 | cross_leg_left | 왼다리 꼬기 |
| 5 | p5 | lean_right | 오른쪽 기대기 |
| 6 | p6 | lean_left | 왼쪽 기대기 |
| 7 | p7 | turtle_neck | 거북목 (등은 닿고 어깨 부분은 떠 있음) |

정의는 `posture_names.py` 한 곳에만 있고, 변환·학습·서버·리포트·시뮬레이터가 모두 거기서 가져옵니다.
예전 7종 데이터/모델은 의미가 달라서(p7이 앉지않음 → 거북목) 새 라벨과 호환되지 않습니다.

## 지금 상태 (센서 도착 전)
서버는 예전 7종 모델 그대로 켜집니다. 수정된 서버·리포트·시뮬레이터는 norm_stats 에
`label_names` 가 없으면 예전 이름표를 쓰도록 되어 있어서, 새 모델로 교체하기 전에는 동작이 같습니다.

## ★ 실측 학습 — 지금 쓰는 경로 (2026-10-22)
`data/raw_64ch/` (ml/collect_data.py --port-back 으로 모은 64ch CSV) 를 바로 읽는다. 아래 1~3단계(collect_back / prepare_chair_data) 없이 된다.
저장소 루트에서:
```
python ml/train_posture_cnn_8cls.py     # 사람 단위 평가(LOPO) + 혼동행렬 + 전체 인원으로 최종 학습
python ml/export_tflite_8cls.py         # TFLite 변환 + 앱 입력/출력 shape 검사 + model_io 기록
```
- 결과: `ml/posture_model_8cls.pt`, `ml/posture_model_8cls.tflite`, `ml/norm_stats_8cls.json`, `ml/runs/8cls/` (confusion_lopo.png/csv, lopo_report.json)
- 점검에서 걸린 파일은 이름에 `_reject` 를 붙이면 학습에서 빠진다.
- json 하나에 앱 키(`label_order`, `model_io`)와 서버 키(`label_classes`, `sensor_cols_order`)가 모두 있다.
- 앱 반입: `posture_model_8cls.tflite` → `assets/model/posture_model.tflite`, `norm_stats_8cls.json` → `assets/model/norm_stats.json`.
  **앱 쪽 8클래스 수정(posture_class.dart 에 turtleNeck id 7, 전처리기 kExpectedLabelOrder 8개)이 먼저 들어가야** 로드된다.
- 서버 교체: `posture_model_8cls.pt` → `posture_model_64ch.pt`, `norm_stats_8cls.json` → `norm_stats_64ch.json` (4단계 주의사항 동일).
- 같은 사람이 날짜를 바꿔 다시 잰 파일(예: person=`aro1022`)은 이름 뒤 숫자를 떼어 같은 사람(`aro`)으로 평가한다.
- 2026-10-22 결과
  - 4명 28파일 (아로 3자세·다혜 앉지않음 미수집): LOPO 평균 55.9%
  - + 아로 1022 재측정 8파일 (feat/aro) = 36파일: LOPO 평균 **64.3%**. 약한 자세: 거북목 29%, 정자세 36%, 오른다리 꼬기 58%

## 1. 수집 (센서 도착 후)
```
pip install pyserial
python collect_back.py ports
python collect_back.py tap  --seat-port COM3 --back-port COM4        # 등받이 채널 위치 확인
python collect_back.py menu --person aro --repeat 3 --seat-port COM3 --back-port COM4
```
- 참가자마다 `--person` 이름을 다르게 (소문자 영문). 8자세 × 3회 = 24개 파일/인.
- 저장 위치: `data\raw_back\<자세>\...csv`. 점검에서 걸린 파일은 파일명에 `_reject` 를 붙여 두면 변환 때 빠집니다.
- 목표: 외부 5~6명, 남성 포함.

## 2. 변환
```
python -m ml.prepare_chair_data --source csvdir --csv-dir data\raw_back --out chair_64ch_posture_data_real.csv
```
끝에 클래스별 행 수와 참가자 수가 나옵니다. "이 CSV에 없는 클래스" 경고가 뜨면 그 자세가 수집되지 않은 겁니다.

## 3. 학습 (사람 단위 평가)
```
python train_posture_cnn_64ch_dummy.py --data chair_64ch_posture_data_real.csv --out-suffix real --holdout-persons dahye
```
- `--holdout-persons` 에 적은 사람은 테스트에만 쓰입니다. 여러 명이면 `yewon,dahye`.
- 참가자가 1명뿐이면 `--holdout-persons` 를 못 씁니다 (프레임 무작위 분리, 점수는 참고용).
- 자세별 정확도와 혼동행렬을 보고 어떤 자세끼리 헷갈리는지 확인하세요. 특히 앞으로 숙이기(p2) ↔ 거북목(p7) ↔ 정자세(p1).
- 결과: `posture_model_64ch_real.pt`, `norm_stats_64ch_real.json`

## 4. 서버 교체
```
ren personal_stats.json personal_stats_old_20261015.json     # 있을 때만 (없으면 오류가 나도 괜찮음)
copy posture_model_64ch_real.pt posture_model_64ch.pt
copy norm_stats_64ch_real.json norm_stats_64ch.json
copy chair_64ch_posture_data_real.csv chair_64ch_posture_data.csv    # 시뮬레이터가 읽는 파일
uvicorn server_64ch:app --reload
```
시작 로그에 `라벨 순서 (8종): ['p0', ... 'p7']` 와 `자세 이름표` 가 나오면 8종입니다.
다른 창에서 `python simulator_64ch_v2.py` 로 p0~p7 이 ✅ 인지 확인하세요 (메뉴가 1~8).

DB(`data\posture.db`)에 7종 시절 기록이 있으면 리포트에서 같은 코드가 다른 자세로 보입니다.
교체 전에 posture.db 를 백업하고, 테스트 기록이면 비우세요.

## 5. 앱 전달물 (TFLite)
```
python convert_to_tflite.py
```
앱 담당에게 넘길 것: `posture_model_64ch.tflite`, `norm_stats_64ch.json` (mean/std 64개, 채널 순서 seat_1~32 → back_1~32), 입력 shape `[1, 1, 64]`, 출력 8개 (위 라벨 표 순서).
`convert_to_tflite.py` 는 테스트셋을 프레임 무작위 분리로 다시 만들어 비교합니다. 사람 단위로 학습했으면
"PyTorch 정확도"는 학습 때 숫자와 다를 수 있고, 변환 손실 확인용 "예측 일치율"만 보면 됩니다.

## 참고: 파이프라인 점검용 더미 (거북목 없음)
```
python -m ml.prepare_chair_data --source npz --npz dummy_windows.npz --out chair_64ch_posture_data_dummy.csv
python train_posture_cnn_64ch_dummy.py --data chair_64ch_posture_data_dummy.csv --out-suffix dummy
```
p7(거북목)은 데이터가 없어서 학습되지 않습니다 (경고가 뜹니다). 이 결과를 서버에 올리지는 마세요.
