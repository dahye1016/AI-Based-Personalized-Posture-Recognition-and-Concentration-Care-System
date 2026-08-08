/*
  sensor_scan.h — SensorScanner: ADC measurement (MUX enable/select, 16ch fast
  scan, spatial reorder). Flattened from 0.1's src/sense/* — class declaration
  and definitions merged here (single translation unit, see board.h note).
  Pin config comes from board.h.
*/

#ifndef SENSOR_SCAN_H_
#define SENSOR_SCAN_H_

#include <Arduino.h>
#include "board.h"

// Settling delay for ADC MUX bus (see fw-design-brief.md Annex A for rationale).
#define MUX_SETTLE_US   0

// Residual-noise cutoff (C5-removed board): reorder() forces raw < 20 -> 0,
// so get_buf() already returns clean values.
#define NOISE_GATE      20

class SensorScanner {
public:
  void init();                  // initial MUX select
  void scan();                  // read every MUX bank -> raw_
  void reorder();               // raw_ -> ordered_ (spatial order, noise-gated)
  int  ordered(int i) const { return ordered_[i]; }
  const int* get_buf() const { return ordered_; }   // 32 spatial values, index 0..31

private:
  void selectMux(int mux_id);   // disable all EN, enable one
  void changeMux(int mux_id);   // disable current EN, enable next
  void read16(int* buf16);      // fast 16ch read of the active MUX bank

  int raw_[MUX_LIST_LEN][NUM_MUX_OUT];   // [mux][ch]
  int ordered_[NUM_REAL_SENSOR_CH];      // spatially ordered
  int activeMux_ = -1;
};

//======================================================================
//  Reorder: MUX channels -> spatial order (bottom row, left-to-right)
//    Row1 (bottom): left-15..left-11, right-4..right-0   (10 cells)
//    Row2 (middle): left-10..left-4,  right-11..right-5  (14 cells)
//    Row3 (top):    left-3..left-0,   right-15..right-12 ( 8 cells)
//======================================================================
struct ReorderEntry { int mux; int ch; };

static const ReorderEntry REORDER_MAP[NUM_REAL_SENSOR_CH] = {
  {0, 15}, {0, 14}, {0, 13}, {0, 12}, {0, 11},   // [ 0..4 ] left-15..left-11
  {1,  4}, {1,  3}, {1,  2}, {1,  1}, {1,  0},   // [ 5..9 ] right-4..right-0
  {0, 10}, {0,  9}, {0,  8}, {0,  7}, {0,  6}, {0,  5}, {0,  4},  // [10..16] left-10..left-4
  {1, 11}, {1, 10}, {1,  9}, {1,  8}, {1,  7}, {1,  6}, {1,  5},  // [17..23] right-11..right-5
  {0,  3}, {0,  2}, {0,  1}, {0,  0},            // [24..27] left-3..left-0
  {1, 15}, {1, 14}, {1, 13}, {1, 12},            // [28..31] right-15..right-12
};

inline void SensorScanner::init() {
  selectMux(0);
}

inline void SensorScanner::selectMux(int mux_id) {
  for (int i = 0; i < MUX_LIST_LEN; i++) {
    digitalWrite(pinMuxEn[enList[i]], 1);       // disable all active En
  }
  digitalWrite(pinMuxEn[enList[mux_id]], 0);     // enable selected En
  activeMux_ = mux_id;
}

inline void SensorScanner::changeMux(int mux_id) {
  digitalWrite(pinMuxEn[enList[activeMux_]], 1);  // disable current
  digitalWrite(pinMuxEn[enList[mux_id]], 0);       // enable next
  activeMux_ = mux_id;
}

//  Fast 16ch read of the active MUX bank (unrolled S0~S3 gray-ish sequence).
inline void SensorScanner::read16(int* buf16) {
  for (int i = 0; i < NUM_MUX_SIG; i++) {
    digitalWrite(pinMuxSig[i], 0);
  }
  delayMicroseconds(MUX_SETTLE_US);
  buf16[0] = analogRead(pinADC);

  digitalWrite(PIN_S0, 1);
  delayMicroseconds(MUX_SETTLE_US);
  buf16[1] = analogRead(pinADC);
  digitalWrite(PIN_S1, 1);
  delayMicroseconds(MUX_SETTLE_US);
  buf16[3] = analogRead(pinADC);
  digitalWrite(PIN_S2, 1);
  delayMicroseconds(MUX_SETTLE_US);
  buf16[7] = analogRead(pinADC);
  digitalWrite(PIN_S3, 1);
  delayMicroseconds(MUX_SETTLE_US);
  buf16[15] = analogRead(pinADC);

  digitalWrite(PIN_S0, 0);
  delayMicroseconds(MUX_SETTLE_US);
  buf16[14] = analogRead(pinADC);
  digitalWrite(PIN_S1, 0);
  delayMicroseconds(MUX_SETTLE_US);
  buf16[12] = analogRead(pinADC);
  digitalWrite(PIN_S2, 0);
  delayMicroseconds(MUX_SETTLE_US);
  buf16[8] = analogRead(pinADC);

  digitalWrite(PIN_S0, 1);
  delayMicroseconds(MUX_SETTLE_US);
  buf16[9] = analogRead(pinADC);
  digitalWrite(PIN_S1, 1);
  delayMicroseconds(MUX_SETTLE_US);
  buf16[11] = analogRead(pinADC);
  digitalWrite(PIN_S0, 0);
  delayMicroseconds(MUX_SETTLE_US);
  buf16[10] = analogRead(pinADC);
  digitalWrite(PIN_S3, 0);
  delayMicroseconds(MUX_SETTLE_US);
  buf16[2] = analogRead(pinADC);

  digitalWrite(PIN_S2, 1);
  delayMicroseconds(MUX_SETTLE_US);
  buf16[6] = analogRead(pinADC);
  digitalWrite(PIN_S1, 0);
  delayMicroseconds(MUX_SETTLE_US);
  buf16[4] = analogRead(pinADC);
  digitalWrite(PIN_S0, 1);
  delayMicroseconds(MUX_SETTLE_US);
  buf16[5] = analogRead(pinADC);
  digitalWrite(PIN_S3, 1);
  delayMicroseconds(MUX_SETTLE_US);
  buf16[13] = analogRead(pinADC);
}

inline void SensorScanner::scan() {
  for (int mux_id = 0; mux_id < MUX_LIST_LEN; mux_id++) {
    changeMux(mux_id);
    read16(raw_[mux_id]);
  }
}

inline void SensorScanner::reorder() {
  for (int i = 0; i < NUM_REAL_SENSOR_CH; i++) {
    int v = raw_[REORDER_MAP[i].mux][REORDER_MAP[i].ch];
    ordered_[i] = (v < NOISE_GATE) ? 0 : v;       // noise gate here, once
  }
}

#endif // SENSOR_SCAN_H_
