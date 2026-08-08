/*
  PoseLab Core — lite (flat)

  Board: ESP32-S3-WROOM-1 N16R8. 
  UART0 @ 2,000,000 (CH343P). 50 fps.
  32-cell FSR pressure board, ASCII CSV output only.

  Each frame prints 32 comma-separated sensor values + newline, 
  e.g.: 0, 0, 312, 1540, 823, 0, 0, 0, 0, 0, 0, 0, 245, 1877, 2103, 96, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  Raw ADC (noise-gated).
*/

#include <Arduino.h>
#include "board.h"         // pins + 50fps timer + DIP + button/LED
#include "sensor_scan.h"   // MUX scan + reorder (ADC measurement)

#define BAUD_RATE0      2000000
#define SERIAL_SIZE_TX  2048
#define FRAME_MS        20     // frame period: 20 ms = 50 fps

SensorScanner scanner;

void setup() {
  Serial.setTxBufferSize(SERIAL_SIZE_TX);
  Serial.begin(BAUD_RATE0);

  // Boot banner: leading \n\n so line 1 clears the ROM bootloader log.
  Serial.printf("\n\n==== PoseLab Core (lite) ====\n");
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
  setup_gpioWork();          // button interrupt + NeoPixel startup sweep
  setup_hw_pins();
  scanner.init();

  Serial.printf("SETUP-WD TIMER (%d ms) \n", FRAME_MS);
  setup_wdTimer(FRAME_MS);

  Serial.printf("STREAM- ENTER (lite-flat, ASCII CSV, 32ch)\n");
}

void loop() {
  loop_wdTimer();            // raise timer_flag each 20 ms tick
  loop_gpioWork();           // poll button (long-press -> restart, LED feedback)

  if (timer_flag == true) {
    scanner.scan();
    scanner.reorder();
    sendAsciiFrame();
    timer_flag = false;
  }
}

//  One line: 32 sensor values, comma-separated, newline-terminated.
//  adc[0]..adc[31] are the spatial sensor values (see protocol.json for layout).
void sendAsciiFrame() {
  const int* adc = scanner.get_buf();      // 32 values, index 0..31
  char packet[224];
  sprintf(packet,
    "%4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d, %4d\n",
    adc[0],  adc[1],  adc[2],  adc[3],  adc[4],  adc[5],  adc[6],  adc[7],
    adc[8],  adc[9],  adc[10], adc[11], adc[12], adc[13], adc[14], adc[15],
    adc[16], adc[17], adc[18], adc[19], adc[20], adc[21], adc[22], adc[23],
    adc[24], adc[25], adc[26], adc[27], adc[28], adc[29], adc[30], adc[31]);
  Serial.print(packet);
}
