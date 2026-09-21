#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PostureCare 64채널 모델 — 더미(합성) 데이터로 학습 파이프라인 점검용 학습 스크립트.

⚠️ 이 스크립트가 만드는 모델은 성능 지표가 아니라 "파이프라인이 처음부터
끝까지 에러 없이 도는지" 확인하는 용도다. dummy_windows.npz의 라벨은 자세별
합격 기준(자세별_합격_기준.xlsx)을 그대로 코드로 옮겨 만든 것이기 때문에,
같은 규칙으로 판정하는 채널 통계 몇 개만 봐도 사실상 라벨을 그대로 복원할
수 있다. 그래서 검증 정확도가 매우 높게(심하면 1.000) 나와도 그건 "모델이
자세를 잘 이해해서"가 아니라 "라벨을 만든 규칙과 특징이 겹쳐서"다.
실측 데이터가 들어오면 반드시 실측으로 다시 학습·평가해야 한다.

사용법
------
    python3 ml/train_dummy.py \
        --data data/dummy/dummy_windows.npz \
        --epochs 15 --batch-size 256 --val-frac 0.2 --out runs/dummy_v1

person(가상 인물) 단위로 학습/검증을 나눈다 — 같은 사람의 윈도우가 학습과
검증에 동시에 섞이면 겹치는 구간(윈도우 stride 1초, 길이 5초라 80% 겹침)
때문에 검증 점수가 실제보다 부풀려진다.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from ml.load_dummy import load_windows, load_groups          # noqa: E402
from ml.model import PostureCNN64                             # noqa: E402

ADC_MAX = 4095.0


def person_split(groups: np.ndarray, val_frac: float, seed: int):
    """윈도우가 아니라 '사람' 단위로 학습/검증을 나눈다 (겹치는 윈도우 누수 방지)."""
    persons = np.unique(groups)
    rng = np.random.default_rng(seed)
    rng.shuffle(persons)
    n_val = max(1, int(round(len(persons) * val_frac)))
    val_persons = set(persons[:n_val].tolist())
    val_mask = np.array([p in val_persons for p in groups])
    return ~val_mask, val_mask, sorted(val_persons)


def run_epoch(model, loader, criterion, optimizer, device, train: bool):
    model.train(train)
    total_loss, total_correct, total_n = 0.0, 0, 0
    with torch.set_grad_enabled(train):
        for xb, yb in loader:
            xb, yb = xb.to(device), yb.to(device)
            if train:
                optimizer.zero_grad()
            logits = model(xb)
            loss = criterion(logits, yb)
            if train:
                loss.backward()
                optimizer.step()
            total_loss += loss.item() * xb.size(0)
            total_correct += (logits.argmax(1) == yb).sum().item()
            total_n += xb.size(0)
    return total_loss / total_n, total_correct / total_n


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="PostureCare 64채널 모델 더미데이터 학습")
    p.add_argument("--data", default="data/dummy/dummy_windows.npz")
    p.add_argument("--epochs", type=int, default=15)
    p.add_argument("--batch-size", type=int, default=256)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--val-frac", type=float, default=0.2, help="검증용으로 뺄 '사람' 비율")
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--out", default="runs/dummy_v1", help="체크포인트/리포트 저장 폴더")
    p.add_argument("--cpu", action="store_true", help="GPU 있어도 강제로 CPU 사용")
    a = p.parse_args(argv)

    os.makedirs(a.out, exist_ok=True)
    torch.manual_seed(a.seed)
    np.random.seed(a.seed)

    device = torch.device("cuda" if (torch.cuda.is_available() and not a.cpu) else "cpu")
    print(f"device: {device}")

    print(f"윈도우 로딩: {a.data}")
    X, y, info = load_windows(a.data)
    groups = load_groups(a.data)
    labels = info["labels"]
    print(f"X {X.shape} {X.dtype} · y {y.shape} · 클래스 {len(labels)}개: {labels}")
    if info.get("back_is_synthetic"):
        print("※ 뒤쪽 32채널(back_ch*)은 실측이 아니라 규칙 기반 합성이다.")

    n_persons = len(np.unique(groups))
    if n_persons < 5:
        # 사람이 너무 적으면(예: 실측 초반, 참가자 1~2명) 통째로 나눌 수가 없다.
        # 이럴 땐 윈도우 단위 무작위 분할로 대체하되, 겹치는 윈도우 때문에 검증
        # 점수가 실제보다 부풀려진다는 걸 분명히 알린다.
        print(f"⚠️  인물 수가 {n_persons}명뿐이라 사람 단위 분할을 할 수 없음 — "
              "윈도우 단위 무작위 분할로 대체함. 이 경우 검증 정확도는 신뢰할 수 없다"
              "(같은 사람의 겹치는 윈도우가 학습/검증에 같이 들어감). 참가자가 더 모이면"
              " 다시 사람 단위 분할로 평가해야 한다.")
        rng = np.random.default_rng(a.seed)
        idx = rng.permutation(len(groups))
        n_val = max(1, int(round(len(idx) * a.val_frac)))
        val_idx, train_idx = set(idx[:n_val].tolist()), set(idx[n_val:].tolist())
        val_mask = np.array([i in val_idx for i in range(len(groups))])
        train_mask = ~val_mask
        val_persons = sorted(set(groups[val_mask].tolist()))
    else:
        train_mask, val_mask, val_persons = person_split(groups, a.val_frac, a.seed)
    print(f"학습 {train_mask.sum():,}개 윈도우 / 검증 {val_mask.sum():,}개 윈도우 "
          f"(검증 인물 {len(val_persons)}명: {val_persons[:6]}{'...' if len(val_persons) > 6 else ''})")

    Xn = X.astype(np.float32) / ADC_MAX  # 0~4095 ADC -> 0~1 정규화
    X_train = torch.from_numpy(Xn[train_mask])
    y_train = torch.from_numpy(y[train_mask].astype(np.int64))
    X_val = torch.from_numpy(Xn[val_mask])
    y_val = torch.from_numpy(y[val_mask].astype(np.int64))

    train_loader = DataLoader(TensorDataset(X_train, y_train), batch_size=a.batch_size,
                              shuffle=True, drop_last=False)
    val_loader = DataLoader(TensorDataset(X_val, y_val), batch_size=a.batch_size,
                            shuffle=False, drop_last=False)

    model = PostureCNN64(num_channels=X.shape[2], num_classes=len(labels)).to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=a.lr)
    criterion = nn.CrossEntropyLoss()

    history = {"train_loss": [], "train_acc": [], "val_loss": [], "val_acc": []}
    best_val_acc, best_state = -1.0, None
    t0 = time.time()
    for epoch in range(1, a.epochs + 1):
        tr_loss, tr_acc = run_epoch(model, train_loader, criterion, optimizer, device, train=True)
        va_loss, va_acc = run_epoch(model, val_loader, criterion, optimizer, device, train=False)
        history["train_loss"].append(tr_loss)
        history["train_acc"].append(tr_acc)
        history["val_loss"].append(va_loss)
        history["val_acc"].append(va_acc)
        if va_acc > best_val_acc:
            best_val_acc = va_acc
            best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
        print(f"[{epoch:02d}/{a.epochs}] train_loss={tr_loss:.4f} train_acc={tr_acc:.4f} "
              f"| val_loss={va_loss:.4f} val_acc={va_acc:.4f}")
    print(f"학습 완료 ({time.time()-t0:.1f}초), best val_acc={best_val_acc:.4f}")

    model.load_state_dict(best_state)
    model.eval()

    # ---- 최종 검증셋 리포트 (사람 단위로 완전히 분리된 세트) ----
    with torch.no_grad():
        all_pred, all_true = [], []
        for xb, yb in val_loader:
            logits = model(xb.to(device))
            all_pred.append(logits.argmax(1).cpu().numpy())
            all_true.append(yb.numpy())
    y_pred = np.concatenate(all_pred)
    y_true = np.concatenate(all_true)

    from sklearn.metrics import classification_report, confusion_matrix
    report = classification_report(y_true, y_pred, target_names=labels, digits=3, zero_division=0)
    cm = confusion_matrix(y_true, y_pred, labels=list(range(len(labels))))
    print("\n=== 검증셋 classification report (사람 단위 분리) ===")
    print(report)

    ckpt_path = os.path.join(a.out, "posture_cnn64_dummy.pt")
    torch.save({"model_state": model.state_dict(), "labels": labels,
                "num_channels": int(X.shape[2]), "window_len": int(X.shape[1])}, ckpt_path)
    with open(os.path.join(a.out, "history.json"), "w", encoding="utf-8") as f:
        json.dump(history, f, ensure_ascii=False, indent=2)
    with open(os.path.join(a.out, "val_report.txt"), "w", encoding="utf-8") as f:
        f.write(report)
    np.savetxt(os.path.join(a.out, "confusion_matrix.csv"), cm, fmt="%d", delimiter=",")

    # ---- 진단 플롯 ----
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt

        # 한글 폰트가 없는 환경(리눅스 기본)에서도 깨지지 않도록 플롯 텍스트는 영문으로 둔다.
        BLUE, ORANGE = "#2a78d6", "#eb6834"
        fig, ax = plt.subplots(figsize=(6, 4))
        epochs_x = range(1, a.epochs + 1)
        ax.plot(epochs_x, history["train_acc"], color=BLUE, linewidth=2, label="train")
        ax.plot(epochs_x, history["val_acc"], color=ORANGE, linewidth=2, label="val (person-level split)")
        ax.set_xlabel("epoch")
        ax.set_ylabel("accuracy")
        ax.set_ylim(0, 1.02)
        ax.set_title("PostureCNN64 dummy-data training curve (pipeline check only)")
        ax.legend(frameon=False)
        ax.spines["top"].set_visible(False)
        ax.spines["right"].set_visible(False)
        fig.tight_layout()
        fig.savefig(os.path.join(a.out, "training_curve.png"), dpi=150)
        plt.close(fig)

        fig, ax = plt.subplots(figsize=(6.5, 5.5))
        im = ax.imshow(cm, cmap="Blues")
        ax.set_xticks(range(len(labels)))
        ax.set_yticks(range(len(labels)))
        ax.set_xticklabels(labels, rotation=45, ha="right")
        ax.set_yticklabels(labels)
        ax.set_xlabel("predicted")
        ax.set_ylabel("actual")
        ax.set_title("Validation confusion matrix (person-level split)")
        vmax = cm.max() if cm.max() > 0 else 1
        for i in range(len(labels)):
            for j in range(len(labels)):
                v = cm[i, j]
                ax.text(j, i, str(v), ha="center", va="center",
                        color="white" if v > vmax * 0.6 else "black", fontsize=8)
        fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
        fig.tight_layout()
        fig.savefig(os.path.join(a.out, "confusion_matrix.png"), dpi=150)
        plt.close(fig)
        print(f"플롯 저장: {a.out}/training_curve.png, {a.out}/confusion_matrix.png")
    except ImportError:
        print("matplotlib 없음 — 플롯 생략 (history.json/confusion_matrix.csv는 저장됨)")

    print(f"\n체크포인트 저장: {ckpt_path}")
    is_dummy = any(str(pid).startswith("dummy") for pid in np.unique(groups))
    if is_dummy:
        print("\n⚠️  이 정확도는 더미(합성) 데이터 기준이다. 라벨이 합격 기준 규칙으로 만들어져서"
              "\n    실제보다 쉽게 높은 점수가 나온다 — 파이프라인이 끝까지 도는지 확인하는 용도지"
              "\n    모델 성능 지표가 아니다. 실측 데이터가 들어오면 반드시 이 스크립트를"
              "\n    실측 npz 기준으로 다시 돌려서 재평가해야 한다.")
    else:
        print(f"\n※ 실측 데이터로 학습함 (참가자 {n_persons}명). 등받이 32채널은 여전히 규칙 기반"
              "\n    합성이라는 점은 유의할 것. 참가자 수가 적을수록 검증 결과 신뢰도가 낮으니"
              "\n    (지금처럼 사람 단위 분할이 안 될 정도로 적으면 특히) 섭외 케이스가 더"
              "\n    모이는 대로 이 스크립트를 다시 돌려서 재평가해야 한다.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
