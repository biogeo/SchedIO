// SchedIO.pde
// A sketch for running an Arduino as a scheduled digital output device for
// for millisecond-level precision intervals.
// See the README file for usage notes, the comments here discuss
// implementation.
// Note that at the moment, the name "SchedIO" is a bit misleading, as there is
// only output implemented, not input. That may change some day.
//
// The basic idea is to allow a PC to communicate with the Arduino, sending
// short commands which schedule changes to the voltage levels on the Arduino's
// digital I/O pins. Commands are about four bytes, which at 115200 baud takes
// about .3 ms to send, plus whatever latency is associated with writing to the
// serial port. Therefore there may be some imprecision in the latency to the
// command, but intervals between commands should be precise; in particular, the
// "pulse pin" commands should give nice reliable square pulses of the desired
// width.
//
// The sketch works by establishing a "priority queue" data structure for
// commands. This is implemented pretty brainlessly as a sorted list. Commands
// to set a pin high or low are inserted into the list according to their
// scheduled time. At each iteration of the loop(), all commands at the front of
// the queue which are due (scheduled time <= current time) are popped from the
// queue and executed. In general, it's not expected that the queue will ever
// grow very long, so using a sorted list instead of something more
// sophisticated like a heap is probably fine.
//
// A command sequence consists of two or four bytes. The first byte is the
// command type, the second identifies the output pin being controlled, and the
// remaining bytes (if any) are timing parameters.
//
// Commands:
//    1 <pin>: Set pin high
//    2 <pin>: Set pin low
//    3 <pin> <dur1> <dur2>: Pulse pin high for word(dur1,dur2) ms
//    4 <pin> <dur1> <dur2>: Pulse pin low for word(dur1,dur2) ms
//    5 <pin> <dur1> <dur2>: In word(dur1,dur2) ms, set pin high
//    6 <pin> <dur1> <dur2>: In word(dur1,dur2) ms, set pin low

// Uncomment the following line to cause the on/off to high/low mapping to be
// inverted.
//#define INVERT_SIGNALS

const unsigned long BAUD_RATE = 115200;

#ifdef INVERT_SIGNALS
const byte SIGNAL_ON = LOW;
const byte SIGNAL_OFF = HIGH;
#else
const byte SIGNAL_ON = HIGH;
const byte SIGNAL_OFF = LOW;
#endif

// Initial value of the digital I/O pins
const byte DEFAULT_OUTPUT = SIGNAL_OFF;

// Define command bytes:
const byte
  CMD_NONE      = 0,
  CMD_SET_ON    = 1,
  CMD_SET_OFF   = 2,
  CMD_PULSE_ON  = 3,
  CMD_PULSE_OFF = 4,
  CMD_DELAY_ON  = 5,
  CMD_DELAY_OFF = 6;
const byte LAST_COMMAND = CMD_DELAY_OFF;
const byte
  SCHED_NONE      = 0,
  SCHED_IMMEDIATE = 1,
  SCHED_PULSE     = 2,
  SCHED_DELAY     = 3;

// Queue node type:
struct CommandQueueNode {
  boolean value;
  byte pin;
  unsigned long time;
  CommandQueueNode* next;
};

CommandQueueNode *commandQueueRoot;

void ScheduleCommand(boolean value, byte pin, word delayTime) {
  CommandQueueNode *newNode;
  CommandQueueNode *stepNode;
  unsigned long currentTime;
  currentTime = millis();
  // Allocate a new command node and fill its values
  newNode = (CommandQueueNode*)malloc(sizeof(CommandQueueNode));
  newNode->value = value;
  newNode->pin   = pin;
  newNode->time  = currentTime + (unsigned long)delayTime;
  newNode->next  = commandQueueRoot;
  if (commandQueueRoot && commandQueueRoot->time < newNode->time) {
    // This is not the first command executed; find the command immediately before
    // this one to execute and insert this after it
    stepNode = commandQueueRoot;
    while (stepNode->next && stepNode->next->time < newNode->time) {
      stepNode = stepNode->next;
    }
    newNode->next = stepNode->next;
    stepNode->next = newNode;
  } else  {
    // This will be the first command executed.
    commandQueueRoot = newNode;
  }
}

void RunCommands() {
  CommandQueueNode *popNode;
  unsigned long currentTime;
  currentTime = millis();
  while (commandQueueRoot && commandQueueRoot->time <= currentTime) {
    digitalWrite(commandQueueRoot->pin, commandQueueRoot->value);
    popNode = commandQueueRoot;
    commandQueueRoot = commandQueueRoot->next;
    free(popNode);
  }
}

inline boolean IsPinValid(byte pin) {
  return (pin >=2 && pin < NUM_DIGITAL_PINS);
}

void setup() {
  unsigned int i;
  for (i=2; i<NUM_DIGITAL_PINS; i++) {
    pinMode(i,OUTPUT);
    digitalWrite(i,DEFAULT_OUTPUT);
  }
  Serial.begin(BAUD_RATE);
  commandQueueRoot = (CommandQueueNode*)NULL;
}

void loop() {
  static byte currentReadBytes = 0;
  static byte currentCommand   = CMD_NONE;
  static byte currentSchedule  = SCHED_NONE;
  static boolean currentValue  = DEFAULT_OUTPUT;
  static byte currentPin       = 0;
  static byte currentParams[2];
  byte serialInput;
  word pulseDuration;
  // Run any scheduled commands that are due
  RunCommands();
  // Read a byte from serial, if available
  if (Serial.available()) {
    serialInput = Serial.read();
    currentReadBytes++;
    if (currentReadBytes==1) {
      // This is the command byte; make sure it's valid
      if (serialInput >=1 && serialInput <= LAST_COMMAND) {
        currentCommand = serialInput;
        switch (currentCommand) {
          case CMD_SET_ON:
          case CMD_PULSE_ON:
          case CMD_DELAY_ON:
            currentValue = SIGNAL_ON;
            break;
          case CMD_SET_OFF:
          case CMD_PULSE_OFF:
          case CMD_DELAY_OFF:
            currentValue = SIGNAL_OFF;
            break;
        }
        switch (currentCommand) {
          case CMD_SET_ON:
          case CMD_SET_OFF:
            currentSchedule = SCHED_IMMEDIATE;
            break;
          case CMD_PULSE_ON:
          case CMD_PULSE_OFF:
            currentSchedule = SCHED_PULSE;
            break;
          case CMD_DELAY_ON:
          case CMD_DELAY_OFF:
            currentSchedule = SCHED_DELAY;
            break;
        }
      }
    } else if (currentReadBytes==2) {
      // This is the pin byte; handle immediate commands
      currentPin = serialInput;
      if (currentSchedule==SCHED_IMMEDIATE) {
        if (IsPinValid(currentPin)) {
          digitalWrite(currentPin, currentValue);
        }
        currentReadBytes = 0;
      }
    } else {
      // This is a parameter byte
      currentParams[currentReadBytes-3] = serialInput;
      if (currentReadBytes==4) {
        // Done reading parameters, perform command
        if (IsPinValid(currentPin)) {
          pulseDuration = word(currentParams[0],currentParams[1]);
          if (currentSchedule == SCHED_PULSE) {
            digitalWrite(currentPin, currentValue);
            ScheduleCommand(!currentValue, currentPin, pulseDuration);
          } else {
            ScheduleCommand(currentValue, currentPin, pulseDuration);
          }
        }
        currentReadBytes=0;
      }
    }
  }
}
