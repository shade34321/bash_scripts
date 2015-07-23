#!/bin/bash
# Requires bc, gnuplot
# Usage: plotping -a <address> -i <interval> -d (delete temporary files on exit) -x (Don't plot on exit)
# p / t to plot, q to quit

while getopts "a:i:dx" opt; do
    case "$opt" in
    a)  ping_address=$OPTARG
        ;;
    i)  interval=$OPTARG
        ;;
    d)  delete_temp=1
        # Graph manipulation will not be possible after script exits if this option is passed
        ;;
    x)  no_plot=1
        ;;
    esac
done

if [ "$ping_address" = "" ]; then
    echo "Invalid Input. Exiting."
    exit
fi

if [ "$interval" = "" ]; then
    interval=1
fi

rm ping_table pinglog_avg 2> /dev/null

ping $ping_address -i $interval > pinglog_avg &
PID=$!
# Suppresses kill output
disown $PID

echo "Logging to" $(pwd)
echo "(p) to plot vs packets / (t) to plot vs time / (q) to exit"
echo "# Ping results for" $ping_address >> ping_table
echo -e "# Valid-Packets"'\t'"Average-Ping"'\t'"Current-Ping"'\t'"Dropped-Packets"'\t'"Time" >> ping_table

total_ping=0
dropped_packets=0
valid_packets=0
oldseq=0
highest_ping=0
starttime=$(date +%H%M%S)

# For non autoadjusting ping axis
# set ytics 50 nomirror tc lt 3
gnuplot_common=$(echo -n "\
    set title \"$ping_address every $interval s\" font \"Arial,16\"
    set term wxt size 1100,550 font "Arial,12"
    set autoscale
    set y2tics 10 nomirror tc lt 1
    set ylabel \"Milliseconds\"
    set y2label \"Dropped Packets\"
    ")

function plot_graph_packets {
    echo -n "$gnuplot_common""\
    set xrange [1:]
    set xlabel \"Valid Packets\"
    plot \"ping_table\" using 1:2 title \"Average ping\" with lines lt 3, \"ping_table\" using 1:3 title 'Ping' with lines lt 4, \"ping_table\" using 1:4 title 'Dropped Packets' with lines lt 1 axes x1y2
    " | gnuplot -p 2>/dev/null
}

function plot_graph_time {
    currenttime=$(date +%H%M%S)
    echo -n "$gnuplot_common""\
    set xdata time
    set timefmt \"%H%M%S\"
    set xtics format \"%H:%M:%S\"
    set xrange [\"$starttime\":\"$currenttime\"]
    set xtics 10 nomirror
    set xlabel \"Time\"
    plot \"ping_table\" using 5:2 title \"Average ping\" with lines lt 3, \"ping_table\" using 5:3 title 'Ping' with lines lt 4, \"ping_table\" using 5:4 title 'Dropped Packets' with lines lt 1 axes x1y2
    " | gnuplot -p 2>/dev/null
}

function finish {
    echo
    echo "Done."
        if [[ ! $no_plot = 1 ]]; then
            plot_graph_packets
            plot_graph_time
        fi
    kill $PID
        
    if [ "$delete_temp" = 1 ]; then
        rm pinglog_avg ping_table
    fi
}

trap finish EXIT

# Wait for first packet
while true
do
    echo -ne "Waiting for response to first packet..." \\r
    final_line_length=$(tail -n1 pinglog_avg | wc -m)
    
    if [ ! $final_line_length = 0 ]; then
        echo -e '\t\t\t\t\t'"FOUND"
        echo
        break
    fi
done

while :
do
    final_line=$(tail -n1 pinglog_avg)

    echo $final_line | grep -q "Destination"
    grep_error=$?
        
        if [ $grep_error = 0 ]; then
            dropped_packets=$[ $dropped_packets + 1 ]
            seq_def=1
        else
            icmp_sequence=$(echo $final_line | cut -d ":" -f2 | awk '{print $1}' | cut -d "=" -f2)
            seq_def=$[ $icmp_sequence - $oldseq ]
        fi
        
        if [ $grep_error = 1 ] && [ $seq_def -gt 1 ]; then
            dropped_packets=$[ $dropped_packets + $[ $seq_def - 1 ] ]
        else
        if [ $grep_error = 1 ] && [ $seq_def = 1 ]; then
            valid_packets=$[ $valid_packets + 1 ]
            current_ping=$(echo $final_line | cut -d ":" -f2 | awk '{print $3}' | cut -d "=" -f2)

                    # This doesn't work sometimes. I don't know why.
                    if [[ $current_ping > $highest_ping ]]; then
                        highest_ping=$current_ping
                    fi
            
            total_ping=$(echo "$total_ping" + "$current_ping" | bc)
            avg_ping=$(echo $total_ping / $valid_packets | bc -l)

            echo -e $valid_packets'\t\t'${avg_ping::-18}'\t\t'$current_ping'\t\t'$dropped_packets'\t\t'$(date +%H%M%S) >> ping_table
            echo -ne "Valid Packets: "$valid_packets'\t'"Average Ping: "${avg_ping::-18}'\t'"Current Ping: "$current_ping'\t'"Highest Ping: "$highest_ping'\t'"Dropped Packets: "$dropped_packets \\r
        fi
        fi

    oldseq=$icmp_sequence
    
    read -t 0.1 -n 1 key
        if [[ $key = q ]]; then
            exit
        else
        if [[ $key = p ]]; then
            echo -ne \\r
            plot_graph_packets &
        else
        if [[ $key = t ]]; then
            echo -ne \\r
            plot_graph_time &
        else
            echo -ne \\r
        fi
        fi
        fi
    
done
