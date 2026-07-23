#include <HX711-multi.h>

// Pins to the load cell amp
#define CLK A0      // clock pin to the load cell amp
#define DOUT1 A1    // data pin to the first load cell amp
#define DOUT2 A2    // data pin to the second load cell amp
#define DOUT3 A3    // data pin to the third load cell amp
#define TARE_TIMEOUT_SECONDS 4

byte DOUTS[3] = {DOUT1, DOUT2, DOUT3};  // Load cells
#define CHANNEL_COUNT sizeof(DOUTS) / sizeof(byte)

long int results[CHANNEL_COUNT];                // Raw results
float filteredResults[CHANNEL_COUNT] = {0};     // Filtered results

HX711MULTI scales(CHANNEL_COUNT, DOUTS, CLK);

// Streaming parameters
#define STREAM_FREQUENCY 50
#define STREAM_INTERVAL_MS (1000 / STREAM_FREQUENCY)
unsigned long lastStreamTime = 0;

// Low-pass filter parameters
#define CUTOFF_FREQUENCY 5
float alpha;

void setup() {
  Serial.begin(115200);
  pinMode(11, OUTPUT);

  // Calculate filter coefficient based on sampling and cutoff frequencies
  float RC = 1.0 / (2.0 * 3.1416 * CUTOFF_FREQUENCY);
  float dt = 1.0 / STREAM_FREQUENCY;
  alpha = dt / (RC + dt);

  tare();
}

void tare() {
  bool tareSuccessful = false;
  unsigned long tareStartTime = millis();

  while (!tareSuccessful &&
         millis() < (tareStartTime + TARE_TIMEOUT_SECONDS * 1000)) {
    tareSuccessful = scales.tare(20, 10000);
  }
}

void sendFilteredData() {
  unsigned long currentTime = millis();

  Serial.print(currentTime);
  Serial.print(",");

  for (int i = 0; i < scales.get_count(); ++i) {
    Serial.print(static_cast<long>(filteredResults[i]));

    if (i != scales.get_count() - 1) {
      Serial.print(',');
    } else {
      Serial.println();
    }
  }
}

void loop() {
  unsigned long currentTime = millis();

  // Ensure sampling and streaming at a consistent 50 Hz
  if (currentTime - lastStreamTime >= STREAM_INTERVAL_MS) {
    scales.read(results);

    for (int i = 0; i < scales.get_count(); ++i) {
      // Apply the low-pass filter directly to the raw measurement
      filteredResults[i] =
          alpha * results[i] +
          (1 - alpha) * filteredResults[i];
    }

    sendFilteredData();
    lastStreamTime = currentTime;
  }

  // Handle serial input for tare
  if (Serial.available() > 0) {
    while (Serial.available()) {
      Serial.read();
    }

    tare();
  }
}