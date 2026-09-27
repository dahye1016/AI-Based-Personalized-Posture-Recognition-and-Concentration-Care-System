def classify_posture(s1, s2, s3, s4, s5, s6):
    """
    6개 센서값을 받아서 자세를 판정하는 함수
    
    센서 위치:
    s1: 앞 왼쪽   s2: 앞 오른쪽
    s3: 중간 왼쪽 s4: 중간 오른쪽
    s5: 뒤 왼쪽   s6: 뒤 오른쪽
    """

    # 앞/뒤/좌/우 평균값 계산
    front_avg = (s1 + s2) / 2   # 앞쪽 평균
    back_avg  = (s5 + s6) / 2   # 뒤쪽 평균
    left_avg  = (s1 + s3 + s5) / 3  # 왼쪽 평균
    right_avg = (s2 + s4 + s6) / 3  # 오른쪽 평균

    # 1. 다리꼬기 — 좌우 압력 차이가 클 때
    if abs(left_avg - right_avg) > 200:
        return "다리꼬기"

    # 2. 거북목 — 앞쪽 압력이 뒤쪽보다 훨씬 높을 때
    if front_avg > 500 and front_avg - back_avg > 250:
        return "거북목"

    # 3. 기대기 — 뒤쪽 압력이 앞쪽보다 훨씬 높을 때
    if back_avg > 500 and back_avg - front_avg > 250:
        return "기대기"

    # 4. 바른자세 — 위 조건 다 아닐 때
    return "바른자세"


def get_posture_feedback(posture):
    """
    자세별 피드백 메시지 반환
    """
    feedback = {
        "바른자세": {
            "status": "good",
            "message": "좋아요! 바른 자세를 유지하고 있어요 😊",
            "action": None
        },
        "거북목": {
            "status": "warning",
            "message": "거북목 자세가 감지됐어요! 허리를 펴주세요 🐢",
            "action": "진동 알림"
        },
        "기대기": {
            "status": "warning",
            "message": "등받이에 너무 기대고 있어요! 앞으로 조금 당겨주세요 🔙",
            "action": "진동 알림"
        },
        "다리꼬기": {
            "status": "warning",
            "message": "다리를 꼬고 있어요! 골반이 틀어질 수 있어요 ↔️",
            "action": "진동 알림"
        },
    }
    return feedback.get(posture, {"status": "unknown", "message": "알 수 없는 자세", "action": None})