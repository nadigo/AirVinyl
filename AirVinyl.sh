#!/bin/bash
# airvinyl.sh
# Vinyl to airplay - Stream vinyl from Raspberry Pi to any Airplay speaker/s.

### FUNCTIONS ###

trim_File () {
    local trimFile=$1
    local file_size=$2
    if [[ $(stat -c %s $trimFile 2>/dev/null) -gt $file_size ]] ; then
    truncate -s 1024 $trimFile
    echo "Flushed $trimFile @ $(date)" >> $log
    fi
}

player() {  
    case $1 in
        'play')
                # generate ntp file
                [[ -f $ntpFile ]] && rm	$ntpFile 
                wait $!   
                $player -ntp $ntpFile; wait $!
                # build pipePlayer 
                play="/bin/sox -V2 -q -r 48k -b 16 -c 2 -t alsa dsnoop:CARD=sndrpihifiberry,DEV=0 -r 44100 -b 16 -c 2 -t raw - | tee "
                for (( i=0; i<${#players[@]} ;i+=2 )); do 
                    play+=">(cat > \$($player -d 0 -l $latency -p $port -nf $ntpFile -w $wait -v ${players[$i]} ${players[$((i + 1))]} - )) "
                done
                play+="| cat > /dev/null &"
                # START pipePlayer
                eval "$play"
                echo $! > $playerPid ;;

        'stop') kill -9 $(<$playerPid) 2> /dev/null ;;
    esac
}
## END FUNCTIONS ####  

# let's log
scriptPath=$(realpath "$0")
log=$(echo $scriptPath | sed -e 's/\.[^.]*$//').log
touch $log && echo "Started @ $(date)" > $log
exec > >(tee -a $log) ; exec 2>&1 ; sleep .1

# cleaning things up
streamPipe=/tmp/phono.pipe
monitorFile=/tmp/monitor.wav
maxMonitorFile=$(( 500 * 1024 * 1000 ))  #in bytes 
# verify we have a pipe
if [[ ! -p $streamPipe ]] ; then mkfifo -m 777 $streamPipe ; fi
# new monitoring file
[[ -f $monitorFile ]] && rm $monitorFile
touch $monitorFile ; chmod 777 $monitorFile

# /// ToDo ////
# build a UI to detect and select Airplay speakers
# avahi-browse _raop._tcp -rfktp | sed '/\+;wlan/d' | sed '/IPv6/d' | sed -e 's/.*\(;_raop\._tcp;local;\)\(.*\)\(;\).*/\2/'

# speakers config  
source speakers.config
###
players=( `echo ${player1[@]}` `echo ${player2[@]}`)

# start sox recording for sound / silence monitoring
# make sure default alsa capturing device is 'mixed' with dsnoop for simultaneous access

# /// ToDo ////
# find better silence parameters
# silence 1 0.1 1% -1 5.0 -50d

/bin/sox -V2 -q \
-t alsa dsnoop:CARD=sndrpihifiberry,DEV=0 \
-t raw - \
silence 1 0.1 0.1% -1 5.0 -85d \
| cat >> $monitorFile &
sleep 1
echo "Starting sox monitoring SOX pid=$! monitorFile=$monitorFile @ $(date)" >> $log


while [ true ]; do

    until [ "$var1" != "$var2" ]; do
        var1=$(stat -c %s $monitorFile)
        sleep 0.5
        var2=$(stat -c %s $monitorFile)
    done

    # sound detected --> stream to AirPlay
    player play
    echo "Sound Detected starting player pid=$(<$playerPid) @ $(date)" >> $log

    until [ "$var1" == "$var2" ]; do
        trim_File $monitorFile $monitorFileMax
        var1=$(stat -c %s $monitorFile)
        sleep 1
        var2=$(stat -c %s $monitorFile)
    done

    # silence detected --> stop player
    player stop
    echo "Silence Detected killing player pid=$(<raop.pid) @ $(date)" >> $log

done
