#!/bin/bash
# AirVinyl.sh
# Vinyl to airplay - Stream vinyl from Raspberry Pi to any Airplay speaker/s.


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
#if [[ -f $monitorFile ]] ; then rm $monitorFile ; fi
# clear pid files 
rm /tmp/sox.pid 2> /dev/null 
rm /tmp/raop.pid 2> /dev/null 


# start sox recording for sound / silence monitoring
# make sure default alsa capturing device is 'mixed' with dsnoop for simultaneous access 
/bin/sox -V2 -q \
-r 48k -b 8 -c 2 -t alsa default \
-r 44100 -b 8 -c 2 -t wav - \
silence 1 0.1 1% -1 5.0 5% \
| cat >> $monitorFile &
sleep 1
echo "Starting sox monitoring SOX pid=$! monitorFile=$monitorFile @ $(date)" >> $log 

let file_size=(500)\*1024\*1000
trim_File () {
        if [[ $(stat -c %s $1 2>/dev/null) -gt $file_size ]] ; then 
        truncate -s 1024 $1
        echo "Flushed $1 @ $(date)" >> $log 
        fi
}

while [ true ]; do 

            until [ "$var1" != "$var2" ]; do                                         
                #truncate 
                var1=$(stat -c %s $monitorFile)
                sleep 0.5
                var2=$(stat -c %s $monitorFile)
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
                trim_File $monitorFile
                var1=$(stat -c %s $monitorFile)
                sleep 1
                var2=$(stat -c %s $monitorFile)
            done

            # silence detected kill player
            kill $(</tmp/raop.pid)
            sleep 1            
            echo "Silence Detected killing ROAP pid=$(</tmp/raop.pid) @ $(date)" >> $log 

done
