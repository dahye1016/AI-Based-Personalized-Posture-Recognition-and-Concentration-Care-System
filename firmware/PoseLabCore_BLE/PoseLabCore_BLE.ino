/*
  PoseLab Core — BLE (32ch)

  Board: ESP32-S3-WROOM-1 N16R8.
  기존 lite 펌웨어에 BLE Notify를 "추가"한 버전.
  Serial(2,000,000) 출력은 그대로 유지 — 디버그 및 안전망.

  BLE:
    Local Name : Cushion-MDEX
    Service    : 180A
    TX Char    : 2A98  (Notify, 66 bytes)
    Payload    : [0..1] frame_no(uint16 LE) + [2..65] ch0..ch31(uint16 LE)
    Rate       : 10 Hz (50fps 중 5프레임마다 1회)
*/

#include <Arduino.h>
#include <NimBLEDevice.h>
#include "board.h"
#include "sensor_scan.h"

#define BAUD_RATE0      2000000
#define SERIAL_SIZE_TX  2048
#define FRAME_MS        20     // 20 ms = 50 fps

// ── BLE 설정 ────────────────────────────────────────────────
#define BLE_NAME        "Cushion-MDEX"
#define SERVICE_UUID    "180A"
#define TX_CHAR_UUID    "2A98"
#define NOTIFY_DIVIDER  5      // 50fps / 5 = 10 Hz
#define PAYLOAD_SIZE    66     // 2 + 32*2

SensorScanner scanner;

static NimBLEServer*         pServer  = nullptr;
static NimBLECharacteristic* pTxChar  = nullptr;
static bool     deviceConnected = false;
static uint16_t frameNo         = 0;
static uint8_t  notifyCounter   = 0;
static uint8_t  payload[PAYLOAD_SIZE];

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* s, NimBLEConnInfo& info) override {
    deviceConnected = true;
    Serial.printf("\n[BLE] connected\n");
    setNeopixelColor(pin_LED_WS2812C, 0, 120, 255);   // 파랑 = 연결됨
  }
  void onDisconnect(NimBLEServer* s, NimBLEConnInfo& info, int reason) override {
    deviceConnected = false;
    Serial.printf("\n[BLE] disconnected (reason=%d), re-advertising\n", reason);
    setNeopixelColor(pin_LED_WS2812C, 100, 50, 0);    // 앰버 = 대기
    NimBLEDevice::startAdvertising();
  }
  void onMTUChange(uint16_t mtu, NimBLEConnInfo& info) override {
    Serial.printf("[BLE] MTU = %u\n", mtu);
  }
};

void setup_ble() {
  NimBLEDevice::init(BLE_NAME);
  NimBLEDevice::setMTU(517);                  // 66바이트 페이로드에 필요

  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  NimBLEService* pService = pServer->createService(SERVICE_UUID);
  pTxChar = pService->createCharacteristic(
              TX_CHAR_UUID,
              NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  pService->start();

  NimBLEAdvertising* pAdv = NimBLEDevice::getAdvertising();
  pAdv->addServiceUUID(SERVICE_UUID);
  pAdv->setName(BLE_NAME);
  pAdv->enableScanResponse(true);
  NimBLEDevice::startAdvertising();

  Serial.printf("BLE ADVERTISING : name=%s  svc=%s  char=%s\n",
                BLE_NAME, SERVICE_UUID, TX_CHAR_UUID);
}

void setup() {
  Serial.setTxBufferSize(SERIAL_SIZE_TX);
  Serial.begin(BAUD_RATE0);

  Serial.printf("\n\n==== PoseLab Core (BLE 32ch) ====\n");
  uint64_t mac = ESP.getEfuseMac();
  uint8_t mb[6];
  for (int i = 0; i < 6; i++)
    mb[i] = (uint8_t)(mac >> (8 * i));
  Serial.printf("MAC        : %02X:%02X:%02X:%02X:%02X:%02X\n",
                mb[0], mb[1], mb[2], mb[3], mb[4], mb[5]);
  Serial.printf("Chip       : ESP32-S3 rev%d @ %dMHz, Flash %uMB, PSRAM %uKB\n",
                ESP.getChipRevision(), ESP.getCpuFreqMHz(),
                (unsigned)(ESP.getFlashChipSize() / (1024 * 1024)),
                (unsigned)(ESP.getPsramSize() / 1024));

  dip_init();
  Serial.printf("DIP switch : SW1=%s  SW2=%s\n",
                dip_sw1() ? "ON" : "OFF", dip_sw2() ? "ON" : "OFF");

  Serial.printf("SETUP-HW PINS \n");
  setup_gpioWork();
  setup_hw_pins();
  scanner.init();

  setup_ble();

  Serial.printf("SETUP-WD TIMER (%d ms) \n", FRAME_MS);
  setup_wdTimer(FRAME_MS);

  Serial.printf("STREAM- ENTER (Serial CSV 50fps + BLE notify 10Hz)\n");
}

void loop() {
  loop_wdTimer();
  loop_gpioWork();

  if (timer_flag == true) {
    scanner.scan();
    scanner.reorder();

    sendAsciiFrame();          // 기존 시리얼 출력 — 그대로 유지

    if (++notifyCounter >= NOTIFY_DIVIDER) {
      notifyCounter = 0;
      sendBleFrame();
    }
    timer_flag = false;
  }
}

//  기존 lite 펌웨어와 동일. 손대지 않음.
void sendAsciiFrame() {
  const int* adc = scanner.get_buf();
  char packet[224];
  sprintf(packet,
    "%4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d\n",
    adc[0],  adc[1],  adc[2],  adc[3],  adc[4],  adc[5],  adc[6],  adc[7],
    adc[8],  adc[9],  adc[10], adc[11], adc[12], adc[13], adc[14], adc[15],
    adc[16], adc[17], adc[18], adc[19], adc[20], adc[21], adc[22], adc[23],
    adc[24], adc[25], adc[26], adc[27], adc[28], adc[29], adc[30], adc[31]);
  Serial.print(packet);
}

//  BLE 바이너리 프레임 (66 bytes, little-endian)
//    [0..1]  frame_no  — 앱이 패킷 유실을 감지하는 용도
//    [2..65] ch0..ch31 — reorder() 후의 공간 순서 그대로
void sendBleFrame() {
  if (!deviceConnected || pTxChar == nullptr) return;

  const int* adc = scanner.get_buf();
  payload[0] = (uint8_t)(frameNo & 0xFF);
  payload[1] = (uint8_t)(frameNo >> 8);
  for (int i = 0; i < NUM_REAL_SENSOR_CH; i++) {
    uint16_t v = (uint16_t)constrain(adc[i], 0, 4095);
    payload[2 + i * 2]     = (uint8_t)(v & 0xFF);
    payload[2 + i * 2 + 1] = (uint8_t)(v >> 8);
  }
  frameNo++;

  pTxChar->setValue(payload, PAYLOAD_SIZE);
  pTxChar->notify();
}