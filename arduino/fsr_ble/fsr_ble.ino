#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#define SERVICE_UUID        "12345678-1234-1234-1234-123456789012"
#define CHARACTERISTIC_UUID "87654321-4321-4321-4321-210987654321"

#define FSR1_PIN 34
#define FSR2_PIN 35
#define FSR3_PIN 32
#define FSR4_PIN 33
#define FSR5_PIN 25
#define FSR6_PIN 26
#define FSR7_PIN 27
#define FSR8_PIN 14

BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool deviceConnected = false;

class MyServerCallbacks: public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("앱 연결됨!");
  }
  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("앱 연결 끊김");
    BLEDevice::startAdvertising();
  }
};

void setup() {
  Serial.begin(115200);
  Serial.println("BLE 시작...");

  BLEDevice::init("PostureCare_ESP32");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pCharacteristic->addDescriptor(new BLE2902());
  pService->start();

  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->start();
  Serial.println("BLE 광고 시작! 앱에서 연결하세요.");
}

void loop() {
  if (deviceConnected) {
    int v1 = analogRead(FSR1_PIN);
    int v2 = analogRead(FSR2_PIN);
    int v3 = analogRead(FSR3_PIN);
    int v4 = analogRead(FSR4_PIN);
    int v5 = analogRead(FSR5_PIN);
    int v6 = analogRead(FSR6_PIN);
    int v7 = analogRead(FSR7_PIN);
    int v8 = analogRead(FSR8_PIN);

    String data = String(v1) + "," + String(v2) + "," +
                  String(v3) + "," + String(v4) + "," +
                  String(v5) + "," + String(v6) + "," +
                  String(v7) + "," + String(v8);

    pCharacteristic->setValue(data.c_str());
    pCharacteristic->notify();

    Serial.println("전송: " + data);
  }
  delay(500);
}