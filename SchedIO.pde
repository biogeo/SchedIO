// Digital output schedule server
// Commands:
//    1 <pin>: Set pin high
//    2 <pin>: Set pin low
//    3 <pin> <dur1> <dur2>: Pulse pin high for word(dur1,dur2) ms
//    4 <pin> <dur1> <dur2>: Pulse pin low for word(dur1,dur2) ms
//    5 <pin> <dur1> <dur2>: In word(dur1,dur2) ms, set pin high
//    6 <pin> <dur1> <dur2>: In word(dur1,dur2) ms, set pin low

const unsigned long baudRate = 115200;
// Use numDigPins = 14 for e.g., Duemilanova
// Use numDigPins = 54 for Mega 2560
const byte numDigPins = 54;

// Define command bytes:
const byte
  CMD_NONE       = 0,
  CMD_SET_HIGH   = 1,
  CMD_SET_LOW    = 2,
  CMD_PULSE_HIGH = 3,
  CMD_PULSE_LOW  = 4,
  CMD_DELAY_HIGH = 5,
  CMD_DELAY_LOW  = 6;
const byte LAST_COMMAND = CMD_DELAY_LOW;
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
  return (pin >=2 && pin < numDigPins);
}

void setup() {
  unsigned int i;
  for (i=2; i<numDigPins; i++) {
    pinMode(i,OUTPUT);
    digitalWrite(i,LOW);
  }
  Serial.begin(baudRate);
  commandQueueRoot = (CommandQueueNode*)NULL;
}

void loop() {
  static byte currentReadBytes = 0;
  static byte currentCommand   = CMD_NONE;
  static byte currentSchedule  = SCHED_NONE;
  static boolean currentValue  = LOW;
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
          case CMD_SET_HIGH:
          case CMD_PULSE_HIGH:
          case CMD_DELAY_HIGH:
            currentValue = HIGH;
            break;
          case CMD_SET_LOW:
          case CMD_PULSE_LOW:
          case CMD_DELAY_LOW:
            currentValue = LOW;
            break;
        }
        switch (currentCommand) {
          case CMD_SET_HIGH:
          case CMD_SET_LOW:
            currentSchedule = SCHED_IMMEDIATE;
            break;
          case CMD_PULSE_HIGH:
          case CMD_PULSE_LOW:
            currentSchedule = SCHED_PULSE;
            break;
          case CMD_DELAY_HIGH:
          case CMD_DELAY_LOW:
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

