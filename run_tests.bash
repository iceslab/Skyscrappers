#!/bin/bash

if [ $# -ne 3 ]
then
	echo "run_tests.bash <path to SkyscrapersCUDA> <path to boards> <path to results>"
	exit -1
fi

TEST_PROGRAM=$1
TEST_PROGRAM_DIR=$(dirname "${TEST_PROGRAM}")
INPUT_DIR=$2
RESULT_DIR=$3
TIMEOUT_SEC=300 # default is 300

ALGORITHMS_LONG_NAMES=("sequential CPU" "parallel CPU" "basic GPU" "incremental GPU" "shared GPU" "AoS GPU" "SoA GPU")
ALGORITHMS_SHORT_NAMES=("seq" "par" "basic" "inc" "shm" "aos" "soa")

BLOCKS_NUM=(1 2 4 8 16 32 64 128 256 512 1024)
THREADS_NUM=(1 2 4 8 16 32 64 128 256 512 1024)

function runAlgorithm {
	ALGORITHM=$1
	INPUT_FILE=$2
	OUTPUT_FILE=$3

	BLOCKS=$4
	THREADS=$5

	HEADERS=$6

	ALG_SHORT=${ALGORITHMS_SHORT_NAMES[$ALGORITHM]}

	BASE_COMMAND="timeout -k 1 $TIMEOUT_SEC optirun $TEST_PROGRAM $HEADERS"
	WHOLE_COMMAND=""

	if [ $ALGORITHM -eq 0 ]
	then
		WHOLE_COMMAND="$BASE_COMMAND -ms -f ${INPUT_FILE} -r ${OUTPUT_FILE}"
	elif [ $ALGORITHM -eq 1 ]
	then
		WHOLE_COMMAND="$BASE_COMMAND -mc -f ${INPUT_FILE} -r ${OUTPUT_FILE}"
	elif [ $ALGORITHM -le 7 ]
	then
		WHOLE_COMMAND="$BASE_COMMAND -mg ${ALG_SHORT} -b ${BLOCKS} -t ${THREADS} -f ${INPUT_FILE} -r ${OUTPUT_FILE}"
	else
		echo "Algorithm #$ALGORITHM (${ALGORITHMS_LONG_NAMES[$ALGORITHM]}) is not processed"
	fi

	echo "Running \"$WHOLE_COMMAND\""
	eval $WHOLE_COMMAND
}

if [ -e $TEST_PROGRAM ]
then
	if [ -d $INPUT_DIR ]
	then 
		# Create result directory if not exists
		[ -d $RESULT_DIR ] || mkdir $RESULT_DIR
		for (( algorithm=0; algorithm<7; algorithm++ ))
		do
			for file in ${INPUT_DIR}/*
			do
				# Skip directories and invalid paths
				[ -f "$file" ] || continue

				ALG_SHORT=${ALGORITHMS_SHORT_NAMES[$algorithm]}
				OUTPUT_FILE=$(basename -- "$file")
				OUTPUT_FILE="${RESULT_DIR}/${OUTPUT_FILE%.*}_${ALG_SHORT}"

				echo "Running ${ALGORITHMS_LONG_NAMES[$algorithm]} algorithm"
				if [ $algorithm -le 1 ]
				then
					OUTPUT_FILE="${OUTPUT_FILE}_cpu.txt"
					if [ -f $OUTPUT_FILE ]
					then
						echo "File $OUTPUT_FILE exists. Skipping..."
					else
						for (( repeats=1; repeats<=10; repeats++ ))
						do
							echo "Repeat #$repeats"
							if [ $repeats -eq 1 ]
							then
								runAlgorithm $algorithm $file $OUTPUT_FILE 0 0 "-v"
							else
								runAlgorithm $algorithm $file $OUTPUT_FILE 0 0 ""
							fi
						done
					fi
				else
					for blocks in $BLOCKS_NUM
					do
						for threads in $THREADS_NUM
						do
							OUTPUT_FILE="${OUTPUT_FILE}_${blocks}b_${threads}t_gpu.txt"
							if [ -f $OUTPUT_FILE ]
							then
								echo "File $OUTPUT_FILE exists. Skipping..."
							else
								echo "Number of blocks: $blocks, threads $threads"
								for (( repeats=1; repeats<=10; repeats++ ))
								do
									echo "Repeat #$repeats"
									if [ $repeats -eq 1 ]
									then
										runAlgorithm $algorithm $file $OUTPUT_FILE $blocks $threads "-v"
									else
										runAlgorithm $algorithm $file $OUTPUT_FILE $blocks $threads ""
									fi
								done
							fi
						done
					done
				fi

					# If there was a timeout it creates empty file
					touch $OUTPUT_FILE
			done
		done
		rm -f "./lastRun.txt"
		echo "Done testing"
	else
		echo "Input directory doesn't exist"
	fi
	
else
	echo "Invalid path to SkyscrapersCUDA"
fi