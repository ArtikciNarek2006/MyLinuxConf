N_confirm() {
    local response default arg prompt_end

    default=0
    for arg in "$@"; do  
        if [[ "$arg" == '--default-yes' || "$arg" == '--default=yes' || "$arg" == '-y' ]]; then
            default=10
        elif [[ "$arg" == '--default-no' || "$arg" == '--default=no' || "$arg" == '-n' ]]; then
            default=20
            break
        fi
    done

    local bold="\033[1m"
    local reset="\033[0m"

    if [[ $default -eq 10 ]]; then echo -ne "[\033[1mY\033[0m/n]: ";
    elif [[ $default -eq 20 ]]; then echo -ne "[y/\033[1mN\033[0m]: "; 
    else echo -ne "[y/n]: "; fi

    while true; do
        read -r response

        if [[ -z "$response" ]]; then
            if [[ $default -eq 10 ]]; then return 0; fi # Yes
            if [[ $default -eq 20 ]]; then return 1; fi # No
            continue # No default, prompt again
        fi

        case "$response" in
            [yY][eE][sS]|[yY])
                return 0
                ;;
            [nN][oO]|[nN])
                return 1
                ;;
            *)
                if [[ $default -eq 10 ]]; then return 0; fi
                if [[ $default -eq 20 ]]; then return 1; fi
                ;;
        esac

        echo -ne "Enter only y,yes,Y,YES for positive / n,no,N,NO for negative answer: ";
    done
}

N_create_snapsever_sink() {
    local DEFAULT_OUTPUT_ID
    local N_new_sinkId_path
    local N_sinkId_files
    local was_nullglob_on
    local node_name

    shopt -q nullglob && was_nullglob_on=0 || was_nullglob_on=1 # 0 means on, 1 menas off
    shopt -s nullglob

    DEFAULT_OUTPUT_ID=$(wpctl inspect @DEFAULT_AUDIO_SINK@ | awk '$1=="id" {gsub(/,/,"",$2); print $2}')
    N_new_sinkId_path=~/".N_snapserver_sinkId_for_outId-${DEFAULT_OUTPUT_ID}"
    N_sinkId_files=(~/.N_snapserver_sinkId_for_outId-*)
    
    if [ -f "${N_sinkId_files[0]}" ]; then
        echo -e "\033[31mSink(s) already exists.\033[0m Sink id file(s): ${N_sinkId_files[*]}"
    else 
        pactl load-module module-pipe-sink file=/tmp/snapfifo sink_name=Snapcast format=s16le rate=48000 sink_properties="device.description='Snapcast'" > "$N_new_sinkId_path"
        if [ $? -eq 0 ]; then 
            echo -e "\033[32mSink created successfully.\033[0m"
            echo -en "Link Default sink's monitor to snapserver playback? "
            if N_confirm -n; then 
                    node_name=$(wpctl inspect @DEFAULT_AUDIO_SINK@ | grep 'node.name' | cut -d'"' -f2)
                    pw-link $(pw-link -o | grep "$node_name:.*FR") $(pw-link -i | grep 'Snapcast.*FR') && \
                        pw-link $(pw-link -o | grep "$node_name:.*FL") $(pw-link -i | grep 'Snapcast.*FL') && \
                        echo -e "Default sink [$node_name]; \033[32mLinked Successfully.\033[0m" || echo -e "Default sink [$node_name]; \033[31mLinking failed.\033[0m" 
            fi
        else 
            echo -e "\033[31mFailed to create sink.\033[0m"
        fi
    fi

    if [[ $was_nullglob_on -eq 1 ]]; then
        shopt -u nullglob
    fi
}

N_remove_snapserver_sink() {
    local N_sinkId_files
    local sinkId_file
    local sink_id
    local monitor_id
    local was_nullglob_on
    local node_name

    shopt -q nullglob && was_nullglob_on=0 || was_nullglob_on=1 # 0 means on, 1 menas off
    shopt -s nullglob

    N_sinkId_files=(~/.N_snapserver_sinkId_for_outId-*)

    if [ -f "${N_sinkId_files[0]}" ]; then
        for sinkId_file in "${N_sinkId_files[@]}"; do
            monitor_id=$(basename $sinkId_file)
            monitor_id="${monitor_id#.N_snapserver_sinkId_for_outId-}"
            sink_id=$(cat "$sinkId_file")
            node_name=$(wpctl inspect $monitor_id | grep 'node.name' | cut -d'"' -f2)

            echo -e "\033[33mUnlinking sink: ${sink_id} from monitor: ${monitor_id}  ...\033[0m"
            pw-link -d $(pw-link -o | grep "$node_name:.*FR") $(pw-link -i | grep 'Snapcast.*FR') && \
                    pw-link -d $(pw-link -o | grep "$node_name:.*FL") $(pw-link -i | grep 'Snapcast.*FL') \
                && echo -e "\033[32mUnlinked Successfully.\033[0m" \
                || echo -e "\033[33mWarning: Explicit unlinking skipped or failed (audio path may already be gone).\033[0m"

            echo -e "\033[33mRemoving sink: ${sink_id} ...\033[0m" 
            pactl unload-module "${sink_id}"
            if [ $? -eq 0 ]; then
                rm -f "$sinkId_file" && echo -e "\033[32mSink removed successfully.\033[0m"
            else 
                echo -e "\033[31mFailed to remove sink.\033[0m" 
            fi
        done
    else 
        echo -e "\033[31mSink ID file not found.\033[0m Maybe sink is not active" 
    fi

    if [[ $was_nullglob_on -eq 1 ]]; then
        shopt -u nullglob
    fi
}
