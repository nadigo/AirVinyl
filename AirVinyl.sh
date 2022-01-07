#!/bin/bash
#
# AirVinyl.sh
# Vinyl to airplay - Stream vinyl from Raspberry Pi to any Airplay (v2) speakers.


# let's log
scriptPath=$(realpath "$0")
log=$(echo $scriptPath | sed -e 's/\.[^.]*$//').log
touch $log && echo "Started @ $(date)" > $log

exec 2>&1 | tee -a $log 

# ToDo need to build a UI to detect and select Airplay speakers 
# avahi-browse _raop._tcp -rfktp | sed '/\+;wlan/d' | sed '/IPv6/d' | sed -e 's/.*\(;_raop\._tcp;local;\)\(.*\)\(;\).*/\2/'
playerIp="192.168.4.192"
port=7000
vol=40

# cleaning things up
streamFile=/tmp/phono.stream
monitorFile=/tmp/monitor.wav
# verify we have a pipe 
if [[ ! -p $streamFile ]] ; then mkfifo -m 777 $streamFile ; fi
# new monitoring file 
if [[ -f $monitorFile ]] ; then rm $monitorFile ; fi
# clear pid files 
rm /tmp/sox.pid 2> /dev/null 
rm /tmp/raop.pid 2> /dev/null 


# start sox recording for sound / silence monitoring
# make sure default alsa capturing device is 'mixed' with dsnoop for simultaneous access 
/bin/sox -V2 -q \
-r 48k -b 16 -c 2 -t alsa default \
-r 44100 -b 16 -c 2 -t wav $monitorFile \
silence 1 0.1 3% -1 3.0 3% &
sleep 1
echo "Starting sox monitoring SOX pid=$! monitorFile=$monitorFile @ $(date)" >> $log 


while [ true ]; do 
            until [ "$var1" != "$var2" ]; do
                var1=$(stat -c %s $monitorFile)
                sleep 0.5
                var2=$(stat -c %s $monitorFile)

                # ToDo need to transact file when it's getting too big
                
                #if [[ $(stat -c %s $monitorFile 2>/dev/null) -gt 512000 ]] ; then 
                #echo '' > $monitorFile ; 
                #echo "Flushed $monitorFile @ $(date)" >> $log 
                #var1=$var2+1
                #sleep 0.5
                #fi
            done

            # sound detected stream from the soundcard input to RAOP player 
            /bin/sox -V2 -q \
            -r 48k -b 16 -c 2 -t alsa ADC \
            -r 44100 -b 16 -c 2 -t wav - \
            | /usr/bin/raop_play -p $port -v $vol $playerIp - &
            echo $! > /tmp/raop.pid 
            sleep 1
            echo "Sound Detected starting ROAP pid=$(</tmp/raop.pid) @ $(date)" >> $log 


            until [ "$var1" == "$var2" ]; do
                var1=$(stat -c %s $monitorFile)
                sleep 1
                var2=$(stat -c %s $monitorFile)
            done

            # silence detected kill player
            kill $(</tmp/raop.pid)
            sleep 1            
            echo "Silence Detected killing ROAP pid=$(</tmp/raop.pid) @ $(date)" >> $log 

done



