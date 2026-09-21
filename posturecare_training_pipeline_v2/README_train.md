# PostureCare 64채널 모델 학습 파이프라인 (더미데이터용)

팀원 클로드가 만든 `dummy_windows.npz`(60,000개, (50,64) 윈도우)를 그대로
읽어서 PostureCNN64 모델을 학습시키는 스크립트예요.

## 폴더 구조

```
posturecare_training/
├── ml/
│   ├── load_dummy.py     ← 팀원분 파일 그대로 (윈도우 로더)
│   ├── model.py           ← PostureCNN64 모델 정의 (새로 작성)
│   └── train_dummy.py     ← 학습 스크립트 (새로 작성)
├── data/dummy/             ← dummy_windows.npz, dummy_sessions_meta.csv를 여기에 넣기
│                              (용량이 커서 이 zip에는 빼뒀어요, 받은 파일 그대로 복사하면 됨)
└── runs/dummy_v1/          ← 이번에 실행한 결과물
    ├── posture_cnn64_dummy.pt   (학습된 모델 체크포인트)
    ├── training_curve.png
    ├── confusion_matrix.png
    ├── confusion_matrix.csv
    ├── val_report.txt
    └── history.json
```

## 쓰는 법

1. `dummy_windows.npz`, `dummy_sessions_meta.csv`를 `data/dummy/`에 넣기
   (팀원분한테 받은 그 파일 그대로).
2. 아래 명령으로 학습:

```bash
python3 -m ml.train_dummy --data data/dummy/dummy_windows.npz \
    --epochs 15 --batch-size 256 --out runs/dummy_v1
```

## 뭘 하는 스크립트인가

- `ml/model.py`의 `PostureCNN64`는 (50프레임, 64채널) 윈도우를 입력받는
  1D-CNN이에요. 시간축(50프레임)에 대해 합성곱 → 풀링 → 완전연결 구조로,
  개요서에 적힌 실제 모델 입력 주기(10Hz × 5초)와 맞춰뒀어요.
- `ml/train_dummy.py`는 **사람(가상 인물) 단위로 학습/검증을 나눠요.**
  윈도우끼리는 1초 간격으로 80%씩 겹치기 때문에, 윈도우 단위로 무작위 분할하면
  같은 사람의 거의 똑같은 윈도우가 학습·검증에 동시에 들어가서 점수가
  부풀려져요. 그래서 검증용 인물(기본 20%)을 통째로 떼어놓고 평가해요.

## 이번 실행 결과 (runs/dummy_v1)

15 epoch 학습 후 검증 정확도 1.000이 나왔어요. 이거 보고 "모델이 완벽하다"고
생각하시면 안 돼요 — 더미 데이터의 라벨 자체가 "자세별 합격 기준" 규칙으로
만들어졌고, 그 규칙이 보는 통계량(좌우 균형, 죽은 채널 등)을 모델도 거의
그대로 배울 수 있어서 나오는 숫자예요. 팀원분 README에도 같은 얘기가
적혀있었죠. 이 결과가 의미하는 건 딱 하나, **"데이터 로딩 → 모델 → 학습 →
평가 파이프라인이 에러 없이 끝까지 돈다"**는 것뿐이에요.

## 실측 데이터가 들어오면

같은 명령을 `data/raw`(실측 CSV)로 만든 윈도우 npz에 대고 다시 돌리면 돼요.
`ml/load_dummy.py`가 요구하는 npz 포맷(sessions_delta 또는 X/y 레이아웃)에
맞춰 실측도 윈도우로 변환하는 스크립트가 필요한데, 이건 팀원분 generate
스크립트의 windowing 로직(`to_windows` 상당 부분)을 실측 CSV에도 적용하면
돼요. 필요하시면 그 변환 스크립트도 만들어드릴게요.
