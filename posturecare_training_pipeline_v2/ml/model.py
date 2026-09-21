#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PostureCare 64채널 자세 분류 모델.

입력 스펙은 개요서 Q4(모델 입력 주기 10Hz, 윈도우 5초 = 50프레임)와
server_64ch.py의 64채널(방석32+등받이32) 정의를 그대로 따른다. 즉 이 모델은
`ml/load_dummy.py`의 `load_windows()`가 주는 (N, 50, 64) 윈도우 배열을
그대로 입력받도록 설계했다.
"""
from __future__ import annotations

import torch
import torch.nn as nn

NUM_CHANNELS = 64
WINDOW_LEN = 50


class PostureCNN64(nn.Module):
    """시간축(50프레임)에 대해 합성곱을 적용하는 1D-CNN 분류기.

    입력:  x (batch, window_len=50, channels=64)  -- load_windows() 그대로
    출력:  logits (batch, num_classes)
    """

    def __init__(self, num_channels: int = NUM_CHANNELS, num_classes: int = 7,
                 dropout: float = 0.3):
        super().__init__()
        self.conv = nn.Sequential(
            nn.Conv1d(num_channels, 64, kernel_size=3, padding=1),
            nn.BatchNorm1d(64),
            nn.ReLU(inplace=True),
            nn.Conv1d(64, 128, kernel_size=3, padding=1),
            nn.BatchNorm1d(128),
            nn.ReLU(inplace=True),
            nn.MaxPool1d(2),                       # 50 프레임 -> 25
            nn.Conv1d(128, 128, kernel_size=3, padding=1),
            nn.BatchNorm1d(128),
            nn.ReLU(inplace=True),
            nn.AdaptiveAvgPool1d(1),                # 시간축 전체를 요약
        )
        self.head = nn.Sequential(
            nn.Flatten(),
            nn.Linear(128, 128),
            nn.ReLU(inplace=True),
            nn.Dropout(dropout),
            nn.Linear(128, num_classes),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # (batch, time, channels) -> Conv1d는 (batch, channels, time)을 기대
        x = x.transpose(1, 2)
        x = self.conv(x)
        return self.head(x)
