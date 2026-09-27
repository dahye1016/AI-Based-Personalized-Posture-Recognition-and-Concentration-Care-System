/*
  board.h — PoseLab Core (lite, flat). Everything that was under src/board/*
  merged into one header: pins + 50fps timer + DIP switch + button/LED.

  0.2 is a FLAT single-sketch build: the whole program is one translation unit
  (PoseLabCore-lite-pre.0.2.ino), so definitions live directly in this header —
  no .cpp, no ODR concern (included exactly once).
  Board: ESP32-S3-WROOM-1 N16R8. SOT: H00-SHOP-16xN/hw-pin-assignment.json.
*/

#ifndef BOARD_H_
#define BOARD_H_

#include <Arduino.h>
#include <Adafruit_NeoPixel.h>
#include "esp_system.h"

//================================================================
//  Pins (was pins.h)
//    MUX: En11(IO9)=Left, En12(IO10)=Right. 2 x 74HC4067 = 32ch.
//================================================================
#define MUX_LIST_LEN    2
const int enList[MUX_LIST_LEN] = {11, 12};   // En11, En12

// Connector EN mapping (index = En number). En0~10 = IDC, En11/12 = onboard.
const int pinMuxEn[13] = {
  39, 40, 41, 42, 19, 20, 3, 45, 46, 38, 47,  // En0 ~ En10
  9, 10                                       // En11 (Left), En12 (Right)
};

#define MUX_74HC4067_OUT    16
#define NUM_MUX_OUT     (MUX_74HC4067_OUT)

#define NUM_REAL_HEIGHT      3     // 3 rows
#define NUM_REAL_WIDTH      14     // max cells per row (row 2)
#define NUM_REAL_SENSOR_CH  32     // total sensor cells

#define NUM_MUX_SIG 4
const int PIN_S0 = 5, PIN_S1 = 6, PIN_S2 = 7, PIN_S3 = 8;
const int pinMuxSig[NUM_MUX_SIG] = {PIN_S0, PIN_S1, PIN_S2, PIN_S3};
const int pinADC = 2;      // MUX Z (ADC1_CH1) = IO2
#define RESOLUTION_BITS (12)

inline void setup_hw_pins() {
  analogReadResolution(RESOLUTION_BITS);
  pinMode(pinADC, INPUT);
  for (int i = 0; i < MUX_LIST_LEN; i++) pinMode(pinMuxEn[enList[i]], OUTPUT);
  for (int i = 0; i < NUM_MUX_SIG; i++)  pinMode(pinMuxSig[i], OUTPUT);
  delay(5);
}

//================================================================
//  DIP switch (was dip_switch.h) — IO11/IO12, active-low.
//================================================================
#define PIN_DIP_SW1  11
#define PIN_DIP_SW2  12

inline void dip_init() {
  pinMode(PIN_DIP_SW1, INPUT_PULLUP);
  pinMode(PIN_DIP_SW2, INPUT_PULLUP);
}
inline bool dip_sw1() { return digitalRead(PIN_DIP_SW1) == LOW; }
inline bool dip_sw2() { return digitalRead(PIN_DIP_SW2) == LOW; }

//================================================================
//  50 fps timer (was timer_50fps.h/.cpp) — 1 MHz tick, 20 ms alarm.
//    Version guard: 3.x timerBegin(freq)/timerAlarm vs 2.0.x prescaler API.
//================================================================
boolean timer_flag = true;   // raised each tick, consumed by loop()

static const int   _ms_to_us     = 1000;
static hw_timer_t* _timer        = NULL;
static ulong       _timer_count     = 0;
static ulong       _timer_count_old = 0;

static void ARDUINO_ISR_ATTR _onTimer() {
  _timer_count++;
}

//  Frame period in ms is passed from the .ino (e.g. 20 = 50 fps) so the rate
//  is visible at the top level, not buried here.
inline void setup_wdTimer(int period_ms) {
#if ESP_ARDUINO_VERSION_MAJOR >= 3
  _timer = timerBegin(1000000);                            // 1 MHz (1 us/tick)
  timerAttachInterrupt(_timer, &_onTimer);
  timerAlarm(_timer, period_ms * _ms_to_us, true, 0);      // auto-reload
#else
  _timer = timerBegin(0, 80, true);
  timerAttachInterrupt(_timer, &_onTimer, true);
  timerAlarmWrite(_timer, period_ms * _ms_to_us, true);
  timerAlarmEnable(_timer);
#endif
}

inline void loop_wdTimer() {
  if (_timer_count_old != _timer_count) {
    timer_flag = true;
    _timer_count_old = _timer_count;
  }
}

//================================================================
//  Button (TACT IO0) + WS2812C LED (IO48) (was gpio.h/.cpp)
//    Long-press 3s -> ESP.restart(). LED sweep on boot.
//================================================================
#define pin_LED_WS2812C 48
// Full constructor (not empty + setPin/updateLength): the empty-ctor path fails
// to init the RMT backend on arduino-esp32 3.x. Works on 2.0.17 too.
static Adafruit_NeoPixel strip0(1, pin_LED_WS2812C, NEO_GRB + NEO_KHZ800);

#define PIN_BTN_USER 0

struct Button {
  const uint8_t PIN;
  char nickName[16];
  bool changed;
  bool isClicked;
  bool isClickedLong;
  bool isClickedVeryLong;
  uint32_t numberKeyPresses;
  uint32_t timeClicked_MS;
};

static Button button1 = { PIN_BTN_USER, "USER", false, false, false, false, 0, 0 };

static void ARDUINO_ISR_ATTR isr1(void* arg) {
  Button* s = static_cast<Button*>(arg);
  s->numberKeyPresses += 1;
  s->changed = true;
}

static void setNeopixelColor(int pinNeopixel, int r, int g, int b) {
  switch (pinNeopixel) {
  case pin_LED_WS2812C:
    strip0.setPixelColor(0, strip0.Color(r, g, b));
    strip0.show();
    break;
  }
}

static void setup_neopixel() {
  strip0.begin();
  strip0.setBrightness(20);

  int delay_term = 200;
  //  Rainbow. 
  setNeopixelColor(pin_LED_WS2812C, 255, 0, 0); delay(delay_term);
  setNeopixelColor(pin_LED_WS2812C, 0, 255, 0); delay(delay_term);
  setNeopixelColor(pin_LED_WS2812C, 0, 0, 255); delay(delay_term);
  setNeopixelColor(pin_LED_WS2812C, 255, 255, 0); delay(delay_term);
  setNeopixelColor(pin_LED_WS2812C, 0, 255, 255); delay(delay_term);
  setNeopixelColor(pin_LED_WS2812C, 255, 0, 255); delay(delay_term);
  setNeopixelColor(pin_LED_WS2812C, 255, 255, 255); delay(delay_term);
  setNeopixelColor(pin_LED_WS2812C, 100, 50, 0);
}

inline void setup_gpioWork() {
  pinMode(button1.PIN, INPUT_PULLUP);
  attachInterruptArg((button1.PIN), isr1, &button1, CHANGE);
  button1.isClicked = 1 - digitalRead(PIN_BTN_USER);

  pinMode(pin_LED_WS2812C, OUTPUT);
  setup_neopixel();
}

static void checkTimeLen(Button *theButton) {
  if (theButton->isClicked) {
    int time_len = millis() - theButton->timeClicked_MS;
    if ((3000 < time_len) && (theButton->isClickedVeryLong == false)) {
      theButton->isClickedVeryLong = true;
      setNeopixelColor(pin_LED_WS2812C, 50, 250, 50);
      delay(200);
      Serial.printf("RESTART \n");
      ESP.restart();
    }
    else if ((1000 < time_len) && (theButton->isClickedLong == false)) {
      theButton->isClickedLong = true;
      setNeopixelColor(pin_LED_WS2812C, 0, 50, 200);
    }
  }
}

inline void loop_gpioWork() {
  if (button1.changed) {
    button1.isClicked = 1 - digitalRead(PIN_BTN_USER);
    button1.timeClicked_MS = millis();
    button1.changed = false;
    if (button1.isClicked == false) {
      button1.isClickedVeryLong = false;
      button1.isClickedLong = false;
      setNeopixelColor(pin_LED_WS2812C, 100, 50, 0);
    }
  }
  checkTimeLen(&button1);
}

#endif // BOARD_H_
