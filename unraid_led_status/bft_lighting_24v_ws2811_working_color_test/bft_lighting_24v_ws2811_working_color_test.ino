#include <FastLED.h>

#define NUM_LEDS 100
#define DATA_PIN 6
#define LED_TYPE WS2811
#define COLOR_ORDER RBG  // Tested and working!

CRGB leds[NUM_LEDS];

void setup() {
  FastLED.addLeds<LED_TYPE, DATA_PIN, COLOR_ORDER>(leds, NUM_LEDS);
  FastLED.setBrightness(100);
}

void loop() {
  static int i = 0;
  static int colorState = 0;

  fill_solid(leds, NUM_LEDS, CRGB::Black);  // Clear strip

  // Cycle through Red, Green, Blue
  switch (colorState) {
    case 0: leds[i] = CRGB::Red; break;
    case 1: leds[i] = CRGB::Green; break;
    case 2: leds[i] = CRGB::Blue; break;
  }

  FastLED.show();
  delay(10);

  i++;
  if (i >= NUM_LEDS) {
    i = 0;
    colorState = (colorState + 1) % 3;  // Next color
  }
}
