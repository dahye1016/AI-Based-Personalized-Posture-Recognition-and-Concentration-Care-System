# 7종(0~6) 64ch 실측 → 학습 → 서버 교체 순서

PowerShell 기준. (파일 이름은 예전 그대로 `RUNBOOK_8cls.md`)

> **앱용 모델(TFLite) 확인·재학습은 `ml/모델_확인및재학습가이드_2026-10-25.md` 를 보세요.**
> 이 문서는 예전 서버(`server_64ch.py`)용 CNN 모델을 실측으로 다시 만드는 순서입니다.

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

정의는 `posture_names.py` 한 곳에만 있고, 변환·학습·서버·리포트·시뮬레이터가 모두 거기서 가져옵니다.
예전 서버 모델(p1~p7, p7=앉지않음)과는 번호 의미가 달라서 새 라벨과 호환되지 않습니다.

## 지금 상태
서버는 예전 모델 그대로 켜집니다. 수정된 서버·리포트·시뮬레이터는 norm_stats 에
`label_names` 가 없으면 예전 이름표를 쓰도록 되어 있어서, 새 모델로 교체하기 전에는 동작이 같습니다.

## 실측 데이터 (2026-10-25)
- `data/raw_64ch/` : 4명(아로·다혜·준서·예원) 7자세 64ch 실측. 점검에서 걸린 파일은 이름 끝에 `_reject`.
- 같은 사람이 날짜를 바꿔 다시 잰 파일(예: person=`aro1022`)은 이름 뒤 숫자를 떼어 같은 사람(`aro`)으로 평가합니다.
- 자세 정의(어깨·엉덩이·무릎 기준)와 측정 직후 확인 방법은 가이드 문서의 "자세 정의" 표를 따릅니다.
- 더미: `data/dummy/chair_64ch_posture_data_dummy.csv.gz` (7자세, `python gen_dummy_spec.py` 로 생성). 더미 성적은 성과로 쓰지 말 것.

## 1. 수집
```
pip install pyserial
python collect_back.py ports
python collect_back.py tap  --seat-port COM3 --back-port COM4        # 등받이 채널 위치 확인
python collect_back.py menu --person aro --repeat 3 --seat-port COM3 --back-port COM4
```
- 참가자마다 `--person` 이름을 다르게 (소문자 영문). 7자세 × 3회 = 21개 파일/인.
- 저장 위치: `data\raw_back\<자세>\...csv`. 점검에서 걸린 파일은 파일명에 `_reject` 를 붙여 두면 변환 때 빠집니다.
- (예원 노트북의 `ml/collect_data.py --port-back` 으로 모으면 `data/raw_64ch/` 에 바로 저장됩니다)

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
- 자세별 정확도와 혼동행렬을 보고 어떤 자세끼리 헷갈리는지 확인하세요. 특히 앞으로 숙이기(p2) ↔ 정자세(p1), 기대기 ↔ 다리 꼬기.
- 결과: `posture_model_64ch_real.pt`, `norm_stats_64ch_real.json`

## 4. 서버 교체
```
ren personal_stats.json personal_stats_old_20261025.json     # 있을 때만 (없으면 오류가 나도 괜찮음)
copy posture_model_64ch_real.pt posture_model_64ch.pt
copy norm_stats_64ch_real.json norm_stats_64ch.json
copy chair_64ch_posture_data_real.csv chair_64ch_posture_data.csv    # 시뮬레이터가 읽는 파일
uvicorn server_64ch:app --reload
```
시작 로그에 `라벨 순서 (7종): ['p0', ... 'p6']` 와 `자세 이름표` 가 나오면 7종입니다.
다른 창에서 `python simulator_64ch_v2.py` 로 p0~p6 이 ✅ 인지 확인하세요.

DB(`data\posture.db`)에 예전 모델 시절 기록이 있으면 리포트에서 같은 코드가 다른 자세로 보입니다.
교체 전에 posture.db 를 백업하고, 테스트 기록이면 비우세요.

## 5. 앱 전달물 (TFLite)
앱용 모델은 서버 CNN 이 아니라 `ml/train_posture_gbt.py` 로 만든 `ml/posture_model_gbt.tflite` 입니다
(입력 [1,128] = 지금 프레임 64 + 캘리브레이션 64, 출력 [1,7]). 자세한 내용은 가이드 문서의 "앱에 붙일 때".
