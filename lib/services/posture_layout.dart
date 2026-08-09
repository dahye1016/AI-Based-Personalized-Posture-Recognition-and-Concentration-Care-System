/// PoseLab Seat 32채널 방석센서 물리 배치 (mdex / bridge/layout.py 기준).
/// 채널 인덱스 0~31 을 앞/뒤/좌/우 구역으로 묶어 규칙 기반 판정에 쓴다.
///
///   ROW2 (뒤/엉덩이) : 24 25 26 27 | 28 29 30 31   (좌4 + 우4)
///   ROW1 (중간)      : 10 11 12 13 14 15 16 | 17 18 19 20 21 22 23  (좌7 + 우7)
///   ROW0 (앞/무릎)   :  0  1  2  3  4 |  5  6  7  8  9   (좌5 + 우5)
class PostureLayout {
  static const int channels = 32;

  static const List<int> front = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
  static const List<int> back = [24, 25, 26, 27, 28, 29, 30, 31];
  static const List<int> left = [
    0, 1, 2, 3, 4, // ROW0 좌
    10, 11, 12, 13, 14, 15, 16, // ROW1 좌
    24, 25, 26, 27, // ROW2 좌
  ];
  static const List<int> right = [
    5, 6, 7, 8, 9, // ROW0 우
    17, 18, 19, 20, 21, 22, 23, // ROW1 우
    28, 29, 30, 31, // ROW2 우
  ];

  static const List<int> all = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
  ];
}
