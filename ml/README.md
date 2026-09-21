# posture-64ch (feat/dahye)

64채널(방석 32 + 등받이 32) 자세 분류 1D-CNN 학습·변환 자산.

## 앱 연동용 모델 (`ml/`) — 최신
`data/raw`(3명, 22파일)로 학습. 앱(`lib/models/posture_class.dart`)의 출력 순서에 맞춘 7클래스.

| 인덱스 | 자세 |
|---|---|
| 0 | not_sitting (앉지않음) |
| 1 | sitting_straight (정자세) |
| 2 | lean_forward (앞으로 숙이기) |
| 3 | cross_leg_right (오른다리꼬기) |
| 4 | cross_leg_left (왼다리꼬기) |
| 5 | lean_right (오른쪽기대기) |
| 6 | lean_left (왼쪽기대기) |

- 앱에 넘길 파일: `ml/posture_model.tflite`, `ml/norm_stats.json`
- 입력: 프레임 1개, `[1, 64, 1]` float32. 값 64개 = 정규화한 ch0~31 + 0 패딩 32개(등받이 없음)
- 정규화: `x_norm[i] = (ch[i] - mean[i]) / std[i]` (i = 0..31, json의 mean/std 사용)
- 출력: `[1, 7]` 점수. argmax가 위 인덱스
- 학습/변환: `python ml/train_posture_cnn.py` → `python ml/export_tflite.py`
- 성능은 **사람 단위 평가**(한 명을 빼고 학습, 그 사람으로 테스트)로 `norm_stats.json`의 `person_split_eval`에 기록. 평균 81.4% (aro 66.7 / dahye 99.7 / yewon 77.9)

아래는 이전(어제) 학습 기록이다.

## 현재 모델 (2026-09-21 재학습)
- 실측 데이터(아로 1인, 12,221프레임) 기반 **7클래스** (p1~p7)
- 등받이 32채널은 실측이 없어 전부 0 → 실질적으로 방석 32채널 모델
- 테스트 정확도 100%는 프레임 단위 무작위 분할 + 1인 데이터라 **참고용**이며 실제 성능이 아님

| p코드 | 자세 |
|---|---|
| p1 | 정자세 (sitting_straight) |
| p2 | 거북목 (lean_forward) |
| p3 | 오른다리꼬기 (cross_leg_right) |
| p4 | 왼다리꼬기 (cross_leg_left) |
| p5 | 오른쪽기대기 (lean_right) |
| p6 | 왼쪽기대기 (lean_left) |
| p7 | 앉지않음 (not_sitting) |

## 어떤 파일이 무엇인가
| 파일 | 설명 |
|---|---|
| `train_posture_cnn_64ch_dummy.py` | **현재 사용하는 학습 스크립트.** 이름에 dummy가 있지만 `--data`, `--out-suffix`로 실측 데이터도 학습함 |
| `ml/prepare_chair_data.py` | 실측 CSV를 `chair_64ch_posture_data.csv` 형식으로 변환 |
| `posture_model_64ch.pt`, `norm_stats_64ch.json` | 현재 학습 결과 (7클래스) |
| `chair_64ch_posture_data.csv` | 학습에 쓴 실측 데이터 |
| `posture_model_64ch.tflite`, `tflite_verification_result.json` | 현재 `.pt`(7클래스)를 `convert_to_tflite.py`로 변환한 앱용 모델과 검증 결과 |

옛 Kaggle 8클래스용 파일(`train_posture_cnn_64ch.py`, 옛 `.tflite`)은 삭제했다(git 기록에는 남아 있음).

## 재학습 방법
자세한 절차는 [TRAIN_IN_POSTURE64CH.md](TRAIN_IN_POSTURE64CH.md) 참고.

```bash
python -m ml.prepare_chair_data --source csvdir --csv-dir data/raw --out chair_64ch_posture_data_real.csv
python train_posture_cnn_64ch_dummy.py --data chair_64ch_posture_data_real.csv --out-suffix real
```

## 더미 학습 데이터
`data/dummy/chair_64ch_posture_data_dummy.csv.gz` (원본 243MB를 gzip으로 38MB로 압축). pandas가 그대로 읽는다.

```bash
python train_posture_cnn_64ch_dummy.py --data data/dummy/chair_64ch_posture_data_dummy.csv.gz --out-suffix dummy
```
