#define FSR_PIN 34

void setup() {
  Serial.begin(115200);
  Serial.println("FSR 센서 테스트!");
}

void loop() {
  int fsrValue = analogRead(FSR_PIN);
  Serial.print("센서값: ");
  Serial.println(fsrValue);
  delay(300);
}