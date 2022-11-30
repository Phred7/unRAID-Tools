#!/bin/bash
FAN_OFF_PWM=0
FAN_LOW_PWM=80
FAN_START_PWM=1
FAN_HIGH_PWM=255
CPU_LOW_TEMP=40
CPU_HIGH_TEMP=870

ARRAY_FAN=/sys/class/hwmon/hwmon4/pwm2

NUM_STEPS=$((FAN_HIGH_TEMP - FAN_OFF_TEMP - 1))
PWM_INCREMENT=$(( (FAN_HIGH_PWM - FAN_LOW_PWM) / NUM_STEPS))
OUTPUT+="Linear PWM Range is "$FAN_LOW_PWM" to "$FAN_HIGH_PWM" in "$NUM_STEPS" increments of "$PWM_INCREMENT$'\n'

CPU_TEMP=`sensors | grep "Package id 0:" | awk '{print $4}' | grep -o '[^+]*' | grep -o '^[^\.]*'`
FAN_LINEAR_PWM=$(( ((HIGHEST_TEMP - FAN_OFF_TEMP - 1) * PWM_INCREMENT) + FAN_LOW_PWM))
echo $FAN_LINEAR_PWM > $ARRAY_FAN
OUTPUT+="Setting pwm to: "$FAN_LINEAR_PWM$'\n'
echo "${OUTPUT}"