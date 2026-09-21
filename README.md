# posture-64ch (feat/dahye)

64채널(방석 32 + 등받이 32) 자세 분류 1D-CNN 학습·변환 자산.

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
| `train_posture_cnn_64ch.py` | **옛 Kaggle 8클래스용.** 현재 모델과 무관 |
| `posture_model_64ch.tflite`, `tflite_verification_result.json` | **옛 8클래스 모델 기준.** 현재 `.pt`와 맞지 않음, 재변환 필요 |

## 재학습 방법
자세한 절차는 [TRAIN_IN_POSTURE64CH.md](TRAIN_IN_POSTURE64CH.md) 참고.

```bash
python -m ml.prepare_chair_data --source csvdir --csv-dir data/raw --out chair_64ch_posture_data_real.csv
python train_posture_cnn_64ch_dummy.py --data chair_64ch_posture_data_real.csv --out-suffix real
```
