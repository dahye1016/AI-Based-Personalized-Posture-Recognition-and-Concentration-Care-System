"""
export_tflite.py — ml/posture_model.pt 를 앱용 TFLite 로 변환하고 검증한다.

경로: PyTorch -> ONNX -> (onnx2tf) -> TFLite float32
검증: data/raw 전체 프레임에 대해 PyTorch 예측과 TFLite 예측이 같은지 확인한다.
      (변환이 깨지지 않았는지 보는 용도이며 모델 성능 평가가 아니다.)
결과: ml/posture_model.tflite, 그리고 ml/norm_stats.json 에 model_io(실제 입출력 shape) 추가

필요: tensorflow, onnx, onnxscript, onnx2tf (tf_env)
실행 (저장소 루트에서):  python ml/export_tflite.py
"""

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import torch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import train_posture_cnn as T  # noqa: E402  (모델·정규화·라벨 순서를 학습과 같은 코드로 공유)

OUT_TFLITE = T.ROOT / "ml" / "posture_model.tflite"


def main():
    import tensorflow as tf

    stats = json.loads(T.OUT_JSON.read_text(encoding="utf-8"))
    assert stats["label_order"] == T.LABEL_ORDER, "norm_stats.json 의 라벨 순서가 학습 코드와 다릅니다."
    mean = np.array(stats["mean"], dtype=np.float32)
    std = np.array(stats["std"], dtype=np.float32)

    model = T.PostureCNN64(len(T.LABEL_ORDER))
    model.load_state_dict(torch.load(T.OUT_PT, map_location="cpu"))
    model.eval()

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        onnx_path = tmp / "posture_model.onnx"
        torch.onnx.export(
            model, torch.randn(1, 1, T.N_INPUT), str(onnx_path),
            input_names=["input"], output_names=["output"], opset_version=13,
        )
        exe = Path(sys.executable).parent / "onnx2tf.exe"
        cmd = [str(exe) if exe.exists() else "onnx2tf", "-i", str(onnx_path), "-o", str(tmp / "tf"), "-osd"]
        subprocess.run(cmd, check=True)
        src = next((tmp / "tf").glob("*float32*.tflite"))
        shutil.copy(src, OUT_TFLITE)

    interp = tf.lite.Interpreter(model_path=str(OUT_TFLITE))
    interp.allocate_tensors()
    inp = interp.get_input_details()[0]
    out = interp.get_output_details()[0]

    df = T.load_raw()
    x = T.to_input(df[T.CH_COLS].values.astype(np.float32), mean, std)
    y = df["posture"].map(T.LABEL_TO_IDX).values

    with torch.no_grad():
        pt_pred = model(torch.tensor(x).unsqueeze(1)).argmax(dim=1).numpy()

    tfl_pred = []
    for row in x:
        interp.set_tensor(inp["index"], row.reshape(inp["shape"]).astype(np.float32))
        interp.invoke()
        tfl_pred.append(int(np.argmax(interp.get_tensor(out["index"]))))
    tfl_pred = np.array(tfl_pred)

    agreement = float((pt_pred == tfl_pred).mean())
    print(f"입력 shape {inp['shape'].tolist()} / 출력 shape {out['shape'].tolist()}")
    print(f"PyTorch vs TFLite 예측 일치율: {agreement * 100:.2f}%  (전체 {len(x)}프레임)")
    print(f"학습 데이터에 대한 정확도(참고, 성능 아님): PT {(pt_pred == y).mean() * 100:.1f}% / TFLite {(tfl_pred == y).mean() * 100:.1f}%")

    stats["model_io"] = {
        "tflite_file": OUT_TFLITE.name,
        "input_shape": inp["shape"].tolist(),
        "input_dtype": "float32",
        "input_layout": f"프레임 1개, 값 {T.N_INPUT}개 = 정규화한 ch0~31 + 0 패딩 32개",
        "output_shape": out["shape"].tolist(),
        "output": "클래스 7개 점수(logit). argmax 가 label_order 의 인덱스",
        "pt_vs_tflite_agreement": agreement,
    }
    T.OUT_JSON.write_text(json.dumps(stats, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"저장: {OUT_TFLITE.relative_to(T.ROOT)}, {T.OUT_JSON.relative_to(T.ROOT)}")
    if agreement < 0.99:
        sys.exit("⚠️ PyTorch 와 TFLite 예측이 1% 이상 다릅니다. 변환을 확인하세요.")


if __name__ == "__main__":
    main()
