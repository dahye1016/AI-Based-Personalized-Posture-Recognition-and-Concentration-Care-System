"""
risk_tracker.py

계획서의 "정상/주의/위험 등급 자동 분류 및 알림" 기능을 구현합니다.
CNN이 매 순간 판정하는 자세 하나만으로는 등급을 못 매겨요 — "몇 초짜리
거북목"인지가 중요하지, 찰나의 판정 하나로는 위험한지 알 수 없거든요.
그래서 "좋은 자세가 아닌 상태가 얼마나 오래 이어지고 있는지"를 계속
추적해서, 그 지속시간을 기준으로 등급을 매깁니다.

동작 방식:
- 좋은 자세(기본: 정자세)가 들어오면 타이머 리셋 -> 등급 '정상'
- 좋은 자세가 아닌 상태가 들어오기 시작하면 타이머 시작
- 그 상태가 계속되는 동안 지속시간이 늘어나고, 임계값을 넘으면 등급 상승
  (경고 임계값 넘으면 '주의', 위험 임계값 넘으면 '위험')
- 중간에 다른 나쁜 자세로 바뀌어도(예: 거북목 -> 다리꼬기) "좋은 자세가
  아닌 상태"가 끊긴 게 아니므로 타이머는 계속 흐름 (자세 종류가 바뀌었다고
  봐주지 않음 — 계속 안 좋은 자세인 건 똑같으므로)

12 알림 설정 화면의 민감도/시간 슬라이더는 warning_sec, danger_sec 값을
바꾸는 것으로 대응시키면 됩니다 (/risk/config로 조절).
"""

import time

DEFAULT_GOOD_CODES = ("p1",)  # 기본: 정자세만 "좋은 자세"로 간주
DEFAULT_WARNING_SEC = 180     # 3분 넘게 나쁜 자세 -> 주의
DEFAULT_DANGER_SEC = 1800     # 30분 넘게 나쁜 자세 -> 위험


class RiskTracker:
    def __init__(self):
        self.good_codes = set(DEFAULT_GOOD_CODES)
        self.warning_sec = DEFAULT_WARNING_SEC
        self.danger_sec = DEFAULT_DANGER_SEC

        self.bad_since = None       # 나쁜 자세가 시작된 시각 (None이면 지금 좋은 자세)
        self.current_code = None    # 가장 최근 판정된 자세 코드
        self.last_notified_level = "정상"  # 알림 중복 방지용 (마지막으로 알린 등급)

    def configure(self, good_codes=None, warning_sec=None, danger_sec=None):
        """12 알림 설정 화면의 슬라이더/토글 값을 반영."""
        if good_codes is not None:
            self.good_codes = set(good_codes)
        if warning_sec is not None:
            self.warning_sec = warning_sec
        if danger_sec is not None:
            self.danger_sec = danger_sec

    def update(self, posture_code: str) -> dict:
        """매 판정마다 호출. 현재 위험 등급 상태를 반환."""
        now = time.time()
        is_good = posture_code in self.good_codes

        if is_good:
            self.bad_since = None
            self.current_code = posture_code
            self.last_notified_level = "정상"
            return self._build_status(duration=0.0, level="정상", posture_code=posture_code)

        # 나쁜 자세: 방금 시작된 거면 타이머 세팅, 이미 진행 중이면 그대로 흐르게 둠
        if self.bad_since is None:
            self.bad_since = now

        self.current_code = posture_code
        duration = now - self.bad_since
        level = self._level_for(duration)

        # 새로 등급이 올라간 순간에만 "알림 필요"를 True로 표시 (매번 True면 스팸이 됨)
        should_notify = level != "정상" and level != self.last_notified_level
        if should_notify:
            self.last_notified_level = level

        status = self._build_status(duration=duration, level=level, posture_code=posture_code)
        status["should_notify"] = should_notify
        return status

    def _level_for(self, duration: float) -> str:
        if duration >= self.danger_sec:
            return "위험"
        elif duration >= self.warning_sec:
            return "주의"
        return "정상"

    def _build_status(self, duration: float, level: str, posture_code: str) -> dict:
        return {
            "posture_code": posture_code,
            "bad_duration_sec": round(duration, 1),
            "risk_level": level,
            "should_notify": False,  # update()에서 필요시 덮어씀
            "config": {
                "good_codes": list(self.good_codes),
                "warning_sec": self.warning_sec,
                "danger_sec": self.danger_sec,
            },
        }

    def status(self) -> dict:
        """지금 상태를 조회만 하고 싶을 때 (타이머 갱신 없이)."""
        if self.bad_since is None:
            duration = 0.0
            level = "정상"
        else:
            duration = time.time() - self.bad_since
            level = self._level_for(duration)
        return self._build_status(duration=duration, level=level, posture_code=self.current_code)
