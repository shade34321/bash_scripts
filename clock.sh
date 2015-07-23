#!/bin/bash
while sleep 1;
do
	# Save the cusor position 
	tput sc

	# tput cup moves the curor to a x y coordinate
	# tput cols returns the number of columns currently in the command window
	tput cup 0 $(($(tput cols)-30))
	date

	# tput rc restores the previously saved cursor position
	tput rc
done
