/*
 * PostureCare - ESP32 FSR 압력센서 → 서버 전송 펌웨어
 *
 * 6개 FSR 압력센서 값을 읽어서 FastAPI 서버의
 * POST /sensor-data 로 전송합니다. (simulator.py 를 대체)
 *
 * 필요: Arduino IDE에 ESP32 보드 패키지 설치
 *       (WiFi.h, HTTPClient.h 는 ESP32 패키지에 기본 포함)
 *
 * ※ ESP8266을 쓴다면 아날로그 입력핀이 A0 1개뿐이라
 *   6개 센서를 직접 못 읽습니다 → 외부 ADC(ADS1115)나 멀티플렉서(CD74HC4067) 필요.
 *   ESP32 사용을 권장합니다.
 */

#include <WiFi.h>
#include <HTTPClient.h>

// ===== 1) 여기를 본인 환경에 맞게 수정 =====
const char* WIFI_SSID     = "여기에_와이파이_이름";
const char* WIFI_PASSWORD = "여기에_와이파이_비밀번호";

// 서버를 띄운 PC의 LAN IP (예: 192.168.0.5). 127.0.0.1 아님!
// PC에서 IP 확인: 맥은 시스템설정>네트워크, 또는 터미널에 `ipconfig getifaddr en0`
const char* SERVER_URL = "http://192.168.0.5:8000/sensor-data";

// ===== 2) FSR 센서 6개를 연결한 ESP32 핀 =====
// ADC1 핀만 사용 (ADC2는 WiFi와 충돌함). 아래 6개가 ADC1.
// 센서 위치:  앞왼 앞오 / 중왼 중오 / 뒤왼 뒤오
const int SENSOR_PINS[6] = {36, 39, 34, 35, 32, 33};

const unsigned long SEND_INTERVAL_MS = 500;  // 0.5초마다 전송

void setup() {
  Serial.begin(115200);
  delay(300);

  // ESP32 ADC는 12비트(0~4095). 풀레인지로 읽도록 설정.
  analogReadResolution(12);
  for (int i = 0; i < 6; i++) {
    analogSetPinAttenuation(SENSOR_PINS[i], ADC_11db); // 0~3.3V 측정
  }

  // 와이파이 연결
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("WiFi 연결 중");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println();
  Serial.print("연결됨! 내 IP: ");
  Serial.println(WiFi.localIP());
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi 끊김, 재연결 시도...");
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    delay(1000);
    return;
  }

  // 6개 센서 읽기 → 서버 자세판정 기준(0~1023)에 맞게 스케일 변환
  int values[6];
  for (int i = 0; i < 6; i++) {
    int raw = analogRead(SENSOR_PINS[i]);       // 0~4095
    values[i] = map(raw, 0, 4095, 0, 1023);     // 0~1023 (시뮬레이터와 동일 범위)
  }

  // JSON 만들기: {"sensor_1":값, ... "sensor_6":값}
  String json = "{";
  for (int i = 0; i < 6; i++) {
    json += "\"sensor_" + String(i + 1) + "\":" + String(values[i]);
    if (i < 5) json += ",";
  }
  json += "}";

  // 서버로 POST
  HTTPClient http;
  http.begin(SERVER_URL);
  http.addHeader("Content-Type", "application/json");
  int code = http.POST(json);

  Serial.print("POST ");
  Serial.print(code);
  Serial.print(" | ");
  Serial.println(json);

  if (code > 0) {
    Serial.println("  응답: " + http.getString());
  }
  http.end();

  delay(SEND_INTERVAL_MS);
}
