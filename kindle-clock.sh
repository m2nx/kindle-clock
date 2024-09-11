#!/bin/sh

PWD=$(pwd)
#LOG="/mnt/us/clock.log"
LOG="/dev/null"
FBINK="/mnt/us/extensions/MRInstaller/bin/PW2/fbink -q"
# FONT="regular=/usr/java/lib/fonts/Palatino-Regular.ttf"
FONT="regular=/mnt/us/fonts/milanting.ttf"
#FONT="regular=/usr/java/lib/fonts/Caecilia_LT_75_Bold.ttf"
CITY="Shanghai"
COND="---"
TEMP="---"

FBROTATE="echo 2 > /sys/devices/platform/imx_epdc_fb/graphics/fb0/rotate"
BACKLIGHT="/sys/devices/platform/imx-i2c.0/i2c-0/0-003c/max77696-bl.0/backlight/max77696-bl/brightness"
BATTERY="/sys/devices/system/wario_battery/wario_battery0/battery_capacity"
# TEMP_SENSOR="/sys/devices/virtual/i2c-adapter/i2c-1/1-0068/papyrus_temperature"


wait_for_wifi() {
  return `lipc-get-prop com.lab126.wifid cmState | grep -e "CONNECTED" | wc -l`
}

update_weather() {
    echo "`date '+%Y-%m-%d_%H:%M:%S'`: update_weather" >> $LOG
    WEATHER=$(curl -s -f -m 5 https://zh-cn.wttr.in/$CITY?format="%C,+%t" )
    RC=$?
    echo "`date '+%Y-%m-%d_%H:%M:%S'`: Got weather data. ($WEATHER, RC=$RC)" >> $LOG
    if [ ! -z "$WEATHER" ]; then
        COND=${WEATHER%,*}
        TEMP=$(echo ${WEATHER##*,} | sed s/+//)
        echo "`date '+%Y-%m-%d_%H:%M:%S'`: Processed weather data. ($TEMP // $COND)" >> $LOG
    fi
}

clear_screen(){
    $FBINK -f -c
    $FBINK -f -c
}

### Prep Kindle...
echo "`date '+%Y-%m-%d_%H:%M:%S'`: ------------- Startup ------------" >> $LOG

### No way of running this if wifi is down.
if [ `lipc-get-prop com.lab126.wifid cmState` != "CONNECTED" ]; then
	exit 1
fi

$FBINK -w -c -f -m -t $FONT,size=20,top=410,bottom=0,left=0,right=0 "Starting Clock..." > /dev/null 2>&1


### stop processes that we don't need
#K4
#/etc/init.d/framework stop
#/etc/init.d/pmond stop
#/etc/init.d/phd stop
#/etc/init.d/cmd stop
#/etc/initd./tmd stop
#/etc/init.d/browserd stop
#/etc/init.d/webreaderd stop
#/etc/init.d/lipc-daemon stop
#/etc/init.d/powerd stop

#PW2/3
stop lab126_gui
stop otaupd
stop phd
stop tmd
stop x
stop todo
stop mcsd

sleep 2

### turn off 270 degree rotation of framebuffer device
eval $FBROTATE

### Set lowest cpu clock
echo powersave > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
### Disable Screensaver
lipc-set-prop com.lab126.powerd preventScreenSaver 1

### set time/weather as we start up
ntpdate -s ntp.ntsc.ac.cn
update_weather
clear_screen

while true; do
    echo "`date '+%Y-%m-%d_%H:%M:%S'`: Top of loop (awake!)." >> $LOG
    ### Backlight off
    echo -n 0 > $BACKLIGHT

    ### Get weather data and set time via ntpdate every hour
    MINUTE=`date "+%M"`
    if [ "$MINUTE" = "00" ]; then
        echo "`date '+%Y-%m-%d_%H:%M:%S'`: Enabling Wifi" >> $LOG
        ### Enable WIFI, disable wifi first in order to have a defined state
    	lipc-set-prop com.lab126.cmd wirelessEnable 1
        TRYCNT=0
        NOWIFI=0
        ### Wait for wifi to come up
    	while wait_for_wifi; do
            if [ ${TRYCNT} -gt 30 ]; then
                ### waited long enough
                echo "`date '+%Y-%m-%d_%H:%M:%S'`: No Wifi... ($TRYCNT)" >> $LOG
                NOWIFI=1
                break
            fi
            WIFISTATE=$(lipc-get-prop com.lab126.wifid cmState)
            echo "`date '+%Y-%m-%d_%H:%M:%S'`: Waiting for Wifi... (try $TRYCNT: $WIFISTATE)" >> $LOG
            ### Are we stuck in READY state?
            if [ "$WIFISTATE" = "READY" ]; then
                ### we have to reconnect
                echo "`date '+%Y-%m-%d_%H:%M:%S'`: Reconnecting to Wifi..." >> $LOG
                /usr/bin/wpa_cli -i wlan0 reconnect

                ### Could also be that kindle forgot the wpa ssid/psk combo
                #if [ wpa_cli status | grep INACTIVE | wc -l ]; then...
            fi
    	    sleep 1
            let TRYCNT=$TRYCNT+1
    	done
        echo "`date '+%Y-%m-%d_%H:%M:%S'`: wifi: `lipc-get-prop com.lab126.wifid cmState`" >> $LOG
        echo "`date '+%Y-%m-%d_%H:%M:%S'`: wifi: `wpa_cli status`" >> $LOG

        if [ `lipc-get-prop com.lab126.wifid cmState` = "CONNECTED" ]; then
            ### Finally, set time
            echo "`date '+%Y-%m-%d_%H:%M:%S'`: Setting time..." >> $LOG
            ntpdate -s ntp.ntsc.ac.cn
            RC=$?
            echo "`date '+%Y-%m-%d_%H:%M:%S'`: Time set. ($RC)" >> $LOG
            update_weather
        fi

        clear_screen
    fi

    ### Disable WIFI
    # lipc-set-prop com.lab126.cmd wirelessEnable 0

    BAT=$(gasgauge-info -s)
    # BAT=$(cat $BATTERY)
    TIME=$(date '+%H:%M')
    DATE=$(date '+%A, %-d. %B %Y')
    # convert to centigrade
    #let INSIDE_TEMP_C="($INSIDE_TEMP_F-32)*5/9"

    DATE=$(date '+%Y 年 %m 月 %d 日')
    WEEK=$(date '+%w')
    if [ $WEEK -eq 0 ]; then
        WEEK_CN='星期天'
    elif [ $WEEK -eq 1 ]; then
        WEEK_CN='星期一'
    elif [ $WEEK -eq 2 ]; then
        WEEK_CN='星期二'
    elif [ $WEEK -eq 3 ]; then
        WEEK_CN='星期三'
    elif [ $WEEK -eq 4 ]; then
        WEEK_CN='星期四'  
    elif [ $WEEK -eq 5 ]; then
        WEEK_CN='星期五'  
    elif [ $WEEK -eq 6 ]; then
        WEEK_CN='星期六'
    fi

    ## adjust coordinates according to display resolution. This is for PW3.
    $FBINK -b -h -c -m -t $FONT,size=150,top=10,bottom=0,left=0,right=0 "$TIME"
    $FBINK -b -h -m -t $FONT,size=20,top=680,bottom=0,left=0,right=0 "$DATE $WEEK_CN"
    $FBINK -b -h   -t $FONT,size=10,top=0,bottom=0,left=1300,right=0 "$BAT%"
  #  $FBINK -b -m -t $FONT,size=20,top=710,bottom=0,left=0,right=0 "$COND"
    $FBINK -b -h -m -t $FONT,size=30,top=850,bottom=0,left=0,right=0 "$COND  $TEMP"
    if [ "$NOWIFI" = "1" ]; then
        $FBINK -b -t $FONT,size=10,top=0,bottom=0,left=50,right=0 "No Wifi!"
    fi
    ### update framebuffer
    $FBINK -w -s

    echo "`date '+%Y-%m-%d_%H:%M:%S'`: Battery: $BAT" >> $LOG

    ### Set Wakeuptimer
	#echo 0 > /sys/class/rtc/rtc1/wakealarm
	#echo ${WAKEUP_TIME} > /sys/class/rtc/rtc1/wakealarm
    NOW=$(date +%s)
    let WAKEUP_TIME="((($NOW + 59)/60)*60)" # Hack to get next minute
    let SLEEP_SECS=$WAKEUP_TIME-$NOW

    ### Prevent SLEEP_SECS from being negative or just too small
    ### if we took too long
    if [ $SLEEP_SECS -lt 5 ]; then
        let SLEEP_SECS=$SLEEP_SECS+60
    fi
    rtcwake -d /dev/rtc1 -m no -s $SLEEP_SECS
    echo "`date '+%Y-%m-%d_%H:%M:%S'`: Going to sleep for $SLEEP_SECS" >> $LOG
	### Go into Suspend to Memory (STR)
	echo "mem" > /sys/power/state
#    exit
done
