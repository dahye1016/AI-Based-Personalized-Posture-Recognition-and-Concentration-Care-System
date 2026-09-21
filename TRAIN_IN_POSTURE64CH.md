# posture-64ch 폴더 안에서 직접 학습하기

이전에 드린 `posturecare_training_pipeline_v2`는 별도로 만든 파이프라인이라
다혜님 실제 서버(`server_64ch.py`)가 쓰는 학습 스크립트(`train_posture_cnn_64ch.py`)
와는 다른 모델 구조였어요 (그건 50프레임 윈도우 입력, 실제 서버 모델은 프레임
하나짜리 입력). 이 문서는 **다혜님의 실제 `posture-64ch` 폴더 안에서, 원본
`train_posture_cnn_64ch.py`를 그대로 쓰는 버전**이에요.

## 지금 상황

`train_posture_cnn_64ch.py`가 읽는 `chair_64ch_posture_data.csv`는 지금
Kaggle ChairPose 데이터셋에 p1~p8을 순번으로 임의 배정한 거예요(실제 우리
posture와 상관없는 자리채움 데이터). 이걸 우리가 실제로 모으고 있는/합성한
posture 데이터로 바꿔서 학습시키는 게 이번 작업이에요.

## posture -> p코드 매핑 (기존에 정해둔 이름 그대로)

| p코드 | 이름 | 우리 posture |
|---|---|---|
| p1 | 정자세 | sitting_straight |
| p2 | 거북목 | lean_forward |
| p3 | 오른다리꼬기 | cross_leg_right |
| p4 | 왼다리꼬기 | cross_leg_left |
| p5 | 오른쪽기대기 | lean_right |
| p6 | 왼쪽기대기 | lean_left |
| p7 | 앉지않음 | not_sitting |
| p8 | 등받이 밀착 자세 | **없음** — 등받이 실측 센서 없이는 수집 불가라 이번엔 제외 |

p2(거북목)를 lean_forward에 매핑한 건 제 판단이에요. 다르게 생각하시면
`--label-map "lean_forward=p2"` 처럼 바꿀 수 있어요.

⚠️ **num_classes가 8 → 7로 줄어듭니다.** `server_64ch.py`가 자세 이름을
8개로 하드코딩해서 화면에 보여주는 부분(`DISPLAY_NAMES` 같은)이 있다면, p8
표시 부분을 손봐야 할 수 있어요. 이건 서버 코드 쪽 작업이라 이 학습
스크립트가 건드리진 않아요 — 필요하시면 그 부분도 도와드릴게요.

## 파일

- `ml/prepare_chair_data.py` — 더미/실측 데이터를 `chair_64ch_posture_data.csv`와
  똑같은 스키마(seat_1~32, back_1~32, Label)로 변환.
- `train_posture_cnn_64ch_dummy.py` — 원본 `train_posture_cnn_64ch.py`와
  **모델 구조·학습 루프가 100% 동일**. 다른 점은 딱 두 가지: 데이터 경로를
  바꿔 넣을 수 있고(`--data`), 저장 파일 이름에 `_dummy`/`_real` 같은 접미사를
  붙여서(`--out-suffix`) 진짜 서버가 쓰는 `posture_model_64ch.pt`를 실수로
  덮어쓰지 않게 했어요.
- `chair_64ch_posture_data_real.csv` — 지금 있는 실측 7개(아로 1인분,
  12,221프레임)를 미리 변환해둔 예시 파일. 바로 학습해볼 수 있어요.

용량이 큰 더미 버전(60,000윈도우 → 692,400프레임, CSV로 243MB)은 여기 넣지
않았어요. 아래처럼 다혜님 컴퓨터에서 직접 만드시면 돼요(팀원분 `dummy_windows.npz`
필요).

## 실행 순서

**1. 폴더 준비**

`ml/prepare_chair_data.py`와 `train_posture_cnn_64ch_dummy.py`를
`C:\Users\jungd\posture-64ch\` 안에 넣으세요. `ml/load_dummy.py`도 같이
필요해요(더미 npz를 읽을 때만 — 이미 저번에 받은 `ml` 폴더에 있어요).

**2. 더미 데이터 변환** (dummy_windows.npz가 있는 위치 기준)

```bash
cd C:\Users\jungd\posture-64ch
python -m ml.prepare_chair_data --source npz --npz data\dummy\dummy_windows.npz --out chair_64ch_posture_data_dummy.csv
```

692,400행짜리 CSV가 나와요(약 240MB, 시간 좀 걸려요).

**3. 학습**

```bash
python train_posture_cnn_64ch_dummy.py --data chair_64ch_posture_data_dummy.csv --out-suffix dummy
```

원본과 똑같이 30 epoch 돌고, `posture_model_64ch_dummy.pt` /
`norm_stats_64ch_dummy.json`이 생겨요. (제가 3 epoch만 시험 삼아 돌려봤을 때도
정상 동작 확인했어요 — 정확도는 100%로 나오는데, 이것도 더미 데이터라 그런
거지 실제 성능이 아니에요. 게다가 원본 스크립트 자체가 프레임을 완전
무작위로 섞어서 나누기 때문에, 같은 5초 구간의 거의 똑같은 연속 프레임이
학습·테스트에 같이 들어갈 수 있어요 — 이건 원본 스크립트의 원래 방식이라
그대로 뒀어요.)

**4. 실측 데이터로도 해보기** (지금 있는 7개, 나중에 더 쌓이면 다시)

```bash
python -m ml.prepare_chair_data --source csvdir --csv-dir data\raw --out chair_64ch_posture_data_real.csv
python train_posture_cnn_64ch_dummy.py --data chair_64ch_posture_data_real.csv --out-suffix real
```

**5. 마음에 들면 실제 서버 파일로 교체**

```bash
copy posture_model_64ch_real.pt posture_model_64ch.pt
copy norm_stats_64ch_real.json norm_stats_64ch.json
```

그다음 서버 재시작(`Ctrl+C` → `uvicorn server_64ch:app --reload`)하면 새 모델을
불러와요. `simulator_64ch_v2.py`로 확인해보세요 — 다만 라벨이 8종에서 7종으로
바뀌었으니 시뮬레이터/서버 쪽에서 p8을 다루는 부분이 있으면 확인이 필요해요.
