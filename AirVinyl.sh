#!/bin/bash
# airVinyl.sh
# Vinyl to airplay - Stream vinyl from Raspberry Pi to any Airplay speaker/s.

## load configuration 
source airVinyl.conf
export PID_LIST=""

# let's log
scriptPath=$(realpath "$0")
log=$(echo $scriptPath | sed -e 's/\.[^.]*$//').log
echo "Started @ $(date)" > $log
exec > >(tee -a $log) ; exec 2>&1 ; sleep .1
#exec 2>&1 >> $log

##   FUNCTIONS   ####  
trim_File () {
    local trimFile=$1
    local maxSize=$2
    if [[ $(stat -c %s $trimFile 2>/dev/null) -gt $maxSize ]] ; then
    truncate -s 1024 $trimFile
    echo "Flushed $trimFile @ $(date)" >> $log
    fi
}

player() { 

    case $1 in
        'play')
                echo "--> player:play" >> $log 
                # generate new ntp file
                [[ -f $STREAMFOLDER/$ntpFile ]] && rm $STREAMFOLDER/$ntpFile  
                $playerCmd -ntp $STREAMFOLDER/$ntpFile 
                #wait $!
                echo "Saved nfp file $ntpFile:$(<$STREAMFOLDER/$ntpFile) @ $(date)" >> $log
                
                # build pipePlayer 
                pipePlayerCmd="stdbuf -i0 -o0 -e0 /bin/sox -V2 -q --ignore-length --buffer $sysLatency -r 48k -b 16 -c 2 -t alsa default -r 44.1k -b 16 -c 2 -t raw - | stdbuf -i0 -o0 -e0 tee "
                for (( i=0; i<$((${#speakers[@]}-2)) ;i+=2 )); do 
                    pipePlayerCmd+=">(stdbuf -i0 -o0 -e0  $playerCmd -d 0 -p $port -l $latency -w $wait -nf $STREAMFOLDER/$ntpFile -v ${speakers[$i]} ${speakers[$((i + 1))]} - ) "
                done
                pipePlayerCmd+="| stdbuf -i0 -o0 -e0 $playerCmd -d 0 -p $port -l $latency -w $wait -nf $STREAMFOLDER/$ntpFile -v ${speakers[-2]} ${speakers[-1]} -"
                
                # START pipePlayer
                echo "pipPlayer CMD:$pipePlayerCmd" >> $log 
                eval "$rtCMD $pipePlayerCmd > /dev/null &" 
                echo $! >$STREAMFOLDER/$playerPid
                PID_LIST+=" $(<$STREAMFOLDER/$playerPid)"
                echo "Started pipePlayer pid=$(<$STREAMFOLDER/$playerPid) @ $(date)" >> $log ;;
                
        'stop') 
                echo "--> player:stop" >> $log 
                kill -9 $(<$STREAMFOLDER/$playerPid) 2> /dev/null 
                echo "killing player pid=$(<$STREAMFOLDER/$playerPid)" >> $log ;;
    esac
}
## END FUNCTIONS ####  


#
#### START ####

## Setting files
# create stream folder if it dosen't exsist 
[[ ! -d $STREAMFOLDER ]] && mkdir -p -m 777 $STREAMFOLDER 
# create pipe if it dosen't exsist 
[[ ! -p $STREAMFOLDER/$PIPENAME ]] && mkfifo -m 777 $STREAMFOLDER/$PIPENAME
# create monitorFile if it dosen't exsist 
[[ -f $STREAMFOLDER/$MONITORFILE ]] && rm $STREAMFOLDER/$MONITORFILE
touch $STREAMFOLDER/$MONITORFILE ;  chmod 777 $STREAMFOLDER/$MONITORFILE 


# start sound / silence monitoring with sox
# make sure default alsa capturing device is 'mixed' with dsnoop for simultaneous access

$rtCMD  /usr/bin/sox \
	-V2 -q --ignore-length \
    -t alsa default \
	-t raw - \
    silence 1 0.1 0.1% -1 5.0 -85d \
	| cat >> $STREAMFOLDER/$MONITORFILE &
PID_LIST+=" $!"
echo "Starting sox monitoring pid=$! monitorFile=$STREAMFOLDER/$MONITORFILE @ $(date)" >> $log
sleep 1

while [ true ]; do

    until [ "$var1" != "$var2" ]; do
        var1=$(stat -c %s $STREAMFOLDER/$MONITORFILE)
        sleep .5
        var2=$(stat -c %s $STREAMFOLDER/$MONITORFILE)
    done
    # sound detected --> player:play
    echo "Sound Detected starting player @ $(date)" >> $log
    player play

    until [ "$var1" == "$var2" ]; do
        trim_File $STREAMFOLDER/$MONITORFILE $maxMONITORFILE
        var1=$(stat -c %s $STREAMFOLDER/$MONITORFILE)
        sleep .5
        var2=$(stat -c %s $STREAMFOLDER/$MONITORFILE)
    done
    # silence detected --> player:stop
    echo "Silence Detected stopping player @ $(date)" >> $log
    player stop

done

trap "kill $PID_LIST" SIGINT
wait $PID_LIST
