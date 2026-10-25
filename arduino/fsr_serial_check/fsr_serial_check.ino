/*
 * 방석 FSR 센서 점검용 스케치 (WiFi/BLE 없음, 시리얼 출력만)
 *
 * 0.1초마다 모든 채널 값을 한 줄로 출력합니다.
 *   예) 120,0,845,33,2010,7
 * PC에서 tools/sensor_check.py 로 15초 동안 채널별 압력을 확인하세요.
 */

// 센서를 꽂은 핀. 배선에 맞게 고치세요.
// 6채널 (firmware/posture_sensor_esp32.ino 와 동일, 앞왼 앞오 / 중왼 중오 / 뒤왼 뒤오)
const int SENSOR_PINS[] = {36, 39, 34, 35, 32, 33};
// 8채널 (arduino/fsr_ble/fsr_ble.ino 와 동일) 을 쓰면 위 줄 대신 아래 줄 사용
// const int SENSOR_PINS[] = {34, 35, 32, 33, 25, 26, 27, 14};

const int NUM_SENSORS = sizeof(SENSOR_PINS) / sizeof(SENSOR_PINS[0]);
const unsigned long INTERVAL_MS = 100;

void setup() {
  Serial.begin(115200);
  analogReadResolution(12);  // 0~4095
  for (int i = 0; i < NUM_SENSORS; i++) {
    analogSetPinAttenuation(SENSOR_PINS[i], ADC_11db);  // 0~3.3V
  }
}

void loop() {
  for (int i = 0; i < NUM_SENSORS; i++) {
    Serial.print(analogRead(SENSOR_PINS[i]));
    if (i < NUM_SENSORS - 1) Serial.print(",");
  }
  Serial.println();
  delay(INTERVAL_MS);
}
