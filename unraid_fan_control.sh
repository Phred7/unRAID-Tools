#!/bin/bash
# unraid_array_fan.sh v0.6 - Fixed Version
# v0.1: By xamindar: First try at it.
# v0.2: Made a small change so the fan speed on low doesn't fluctuate every time the script is run.
# v0.3: It will now enable fan speed change before trying to change it. I missed 
#        it at first because pwmconfig was doing it for me while I was testing the fan.
# v0.4: Corrected temp reading to "Temperature_Celsius" as my new Seagate drive
#        was returning two numbers with just "Temperature".
# v0.5: By Pauven:  Added linear PWM logic to slowly ramp speed when fan is between HIGH and OFF.
# v0.6: By kmwoley: Added fan start speed. Added logging, suppressed unless fan speed is changed.
# FIXED: Added root permission check, fixed CPU temp parsing, and hwmon path verification
# A simple script to check for the highest hard disk temperatures in an array
# or backplane and then set the fan to an apropriate speed. Fan needs to be connected
# to motherboard with pwm support, not array.
# DEPENDS ON:grep,awk,smartctl,hdparm

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

### VARIABLES FOR USER TO SET ###
# Amount of drives in the array. Make sure it matches the amount you filled out below.
NUM_OF_DRIVES=10

# unRAID drives that are in the array/backplane of the fan we need to control
HD[1]=/dev/sdb
HD[2]=/dev/sdc
HD[3]=/dev/sdd
HD[4]=/dev/sde
HD[5]=/dev/sdf
HD[6]=/dev/sdg
HD[7]=/dev/sdh
HD[8]=/dev/sdi
HD[9]=/dev/sdj
HD[10]=/dev/sdk

# Temperatures to change fan speed at
# Any temp between OFF and HIGH will cause fan to run on low speed setting 
FAN_LOW_TEMP=28     # Anything this number and below - fan is off
FAN_HIGH_TEMP=40    # Anything this number or above - fan is high speed
GPU_LOW_TEMP=55
GPU_HIGH_TEMP=70
CPU_LOW_TEMP=40
CPU_HIGH_TEMP=80

# Fan speed settings. Run pwmconfig (part of the lm_sensors package) to determine 
# what numbers you want to use for your fan pwm settings. Should not need to
# change the OFF variable, only the LOW and maybe also HIGH to what you desire.
# The START variable controls the speed to get the fan spinning from 0 
# (Default: 255 to be safe).
# Any real number between 0 and 255.
#
FAN_OFF_PWM=0
FAN_LOW_PWM=10
FAN_START_PWM=1
FAN_HIGH_PWM=255

# Fan device. Depends on your system. pwmconfig can help with finding this out. 
# pwm1 is usually the cpu fan. You can "cat /sys/class/hwmon/hwmon0/device/fan1_input"
# or fan2_input and so on to see the current rpm of the fan. If 0 then fan is off or 
# there is no fan connected or motherboard can't read rpm of fan.
ARRAY_FAN0=/sys/class/hwmon/hwmon3/pwm1
ARRAY_FAN1=/sys/class/hwmon/hwmon3/pwm2
ARRAY_FAN2=/sys/class/hwmon/hwmon3/pwm3
ARRAY_FAN3=/sys/class/hwmon/hwmon3/pwm4
ARRAY_FAN4=/sys/class/hwmon/hwmon3/pwm5
ARRAY_FAN5=/sys/class/hwmon/hwmon3/pwm6
### END USER SET VARIABLES ###

# Verify hwmon paths exist
for fan in "$ARRAY_FAN0" "$ARRAY_FAN1" "$ARRAY_FAN2" "$ARRAY_FAN3" "$ARRAY_FAN4" "$ARRAY_FAN5"; do
    if [ ! -f "$fan" ]; then
        echo "Warning: Fan control file not found: $fan"
        echo "Available hwmon devices:"
        ls -la /sys/class/hwmon/
        exit 1
    fi
done

# Program variables - do not modify
HIGHEST_TEMP=0
CURRENT_DRIVE=1
CURRENT_TEMP=0
OUTPUT=""
FAN_PWM=0

# Linear PWM Logic Variables - do not modify
NUM_STEPS=$((FAN_HIGH_TEMP - FAN_LOW_TEMP - 1))
PWM_INCREMENT=$(( (FAN_HIGH_PWM - FAN_LOW_PWM) / NUM_STEPS))
OUTPUT+="Linear PWM Range is "$FAN_LOW_PWM" to "$FAN_HIGH_PWM" in "$NUM_STEPS" increments of "$PWM_INCREMENT$'\n'

# while loop to get the highest temperature of active drives. 
# If all are spun down then high temp will be set to 0.
while [ "$CURRENT_DRIVE" -le "$NUM_OF_DRIVES" ]
do
  SLEEPING=`hdparm -C ${HD[$CURRENT_DRIVE]} | grep -c standby`
  if [ "$SLEEPING" == "0" ]; then
    CURRENT_TEMP=`smartctl --all ${HD[$CURRENT_DRIVE]} | grep Temperature_Celsius | awk '{print $10}'`
    OUTPUT+=" -- Drive "${HD[$CURRENT_DRIVE]}" temp "$CURRENT_TEMP$'\n'
    if [ "$HIGHEST_TEMP" -le "$CURRENT_TEMP" ]; then
      HIGHEST_TEMP=$CURRENT_TEMP
    fi
  fi
echo ${HD[$CURRENT_DRIVE]}": "$CURRENT_TEMP
  let "CURRENT_DRIVE+=1"
done
OUTPUT+="Highest drive temp is: "$HIGHEST_TEMP$'\n'

# Get CPU temperature and convert to integer (remove decimal places)
CPU_TEMP_RAW=`sensors | grep "Package:" | awk '{print $2}' | sed 's/+//; s/°C//'`
CPU_TEMP=${CPU_TEMP_RAW%.*}  # Remove decimal part to make it an integer

# Get GPU temperature
GPU_TEMP=`nvidia-smi | grep '[[:digit:]]C' | awk '{print $3}' | grep -o '.[^C]'`

# Check if CPU_TEMP is empty or not a number
if ! [[ "$CPU_TEMP" =~ ^[0-9]+$ ]]; then
    echo "Warning: Could not read CPU temperature, defaulting to 0"
    CPU_TEMP=0
fi

# Enable speed change on fans if not already enabled
for fan in "$ARRAY_FAN0" "$ARRAY_FAN1" "$ARRAY_FAN2" "$ARRAY_FAN3" "$ARRAY_FAN4" "$ARRAY_FAN5"; do
    enable_file="${fan}_enable"
    if [ -f "$enable_file" ]; then
        current_enable=`cat "$enable_file" 2>/dev/null`
        if [ "$current_enable" != "1" ]; then
            echo 1 > "$enable_file" 2>/dev/null || echo "Warning: Could not enable fan control for $fan"
        fi
    fi
done

# previous speed
PREVIOUS_SPEED=`cat $ARRAY_FAN0`

# Set the fan speed based on highest temperature
if [ "$HIGHEST_TEMP" -le "$FAN_LOW_TEMP" ]; then
  # set fan to off
  FAN_PWM=$FAN_OFF_PWM
  OUTPUT+="Setting pwm to: "$FAN_OFF_PWM$'\n'
elif [ "$HIGHEST_TEMP" -ge "$FAN_HIGH_TEMP" ]; then
  # set fan to full speed
  FAN_PWM=$FAN_HIGH_PWM
  OUTPUT+="Setting pwm to: "$FAN_HIGH_PWM$'\n'
else
  # Calculate target fan PWM speed as a linear value between FAN_HIGH_PWM and FAN_LOW_PWM
  FAN_LINEAR_PWM=$(( ((HIGHEST_TEMP - FAN_LOW_TEMP - 1) * PWM_INCREMENT) + FAN_LOW_PWM))
  FAN_PWM=$FAN_LINEAR_PWM
fi

FAN_CPU_PWM=0
FAN_GPU_PWM=0

# CPU fan control with integer comparison
if [ "$CPU_TEMP" -gt "$CPU_HIGH_TEMP" ]; then
  FAN_CPU_PWM=$FAN_HIGH_PWM
  OUTPUT+="CPU setting pwm to: "$FAN_HIGH_PWM$'\n'
elif [ "$CPU_TEMP" -gt "$CPU_LOW_TEMP" ]; then
  STEPS=$((CPU_HIGH_TEMP - CPU_LOW_TEMP - 1))
  INC=$(( (FAN_HIGH_PWM - FAN_LOW_PWM) / STEPS))
  FAN_LINEAR_PWM=$(( ((CPU_TEMP - CPU_LOW_TEMP - 1) * INC) + FAN_LOW_PWM))
  FAN_CPU_PWM=$FAN_LINEAR_PWM
  OUTPUT+="CPU setting pwm to: "$FAN_LINEAR_PWM$'\n'
fi

# GPU fan control
if [ "$GPU_TEMP" -gt "$GPU_HIGH_TEMP" ]; then
  FAN_GPU_PWM=$FAN_HIGH_PWM
  OUTPUT+="GPU setting pwm to: "$FAN_HIGH_PWM$'\n'
elif [ "$GPU_TEMP" -gt "$GPU_LOW_TEMP" ]; then
  STEPS=$((GPU_HIGH_TEMP - GPU_LOW_TEMP - 1))
  INC=$(( (FAN_HIGH_PWM - FAN_LOW_PWM) / STEPS))
  FAN_LINEAR_PWM=$(( ((GPU_TEMP - GPU_LOW_TEMP - 1) * INC) + FAN_LOW_PWM))
  FAN_GPU_PWM=$FAN_LINEAR_PWM
  OUTPUT+="GPU setting pwm to: "$FAN_LINEAR_PWM$'\n'
fi

# Use the highest required fan speed
if [ "$FAN_PWM" -lt "$FAN_CPU_PWM" ]; then
  FAN_PWM=$FAN_CPU_PWM
  echo "CPU takeover: "$FAN_CPU_PWM
fi

if [ "$FAN_PWM" -lt "$FAN_GPU_PWM" ]; then
  FAN_PWM=$FAN_GPU_PWM
  echo "GPU takeover: "$FAN_GPU_PWM
fi

# Apply fan speed to all fans
echo $FAN_PWM > $ARRAY_FAN0
echo $FAN_PWM > $ARRAY_FAN1
echo $FAN_PWM > $ARRAY_FAN2
echo $FAN_PWM > $ARRAY_FAN3
echo $FAN_PWM > $ARRAY_FAN4
echo $FAN_PWM > $ARRAY_FAN5

# produce output if the fan speed was changed
CURRENT_SPEED=`cat $ARRAY_FAN0`
if [ "$PREVIOUS_SPEED" -ne "$CURRENT_SPEED" ]; then
  echo "Fan speed has changed."
  echo -e "${OUTPUT}"
else
  echo "Fan speed unchanged."
fi
echo "Highest drive: "$HIGHEST_TEMP"°C("$FAN_LOW_TEMP"/"$FAN_HIGH_TEMP"). CPU: "$CPU_TEMP"°C("$CPU_LOW_TEMP"/"$CPU_HIGH_TEMP"). GPU: "$GPU_TEMP"°C("$GPU_LOW_TEMP"/"$GPU_HIGH_TEMP"). Current pwm: "$CURRENT_SPEED