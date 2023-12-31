#!/bin/bash
#
# This script generates the post files for the specified node.
#
## Usage:
#
#   ./generate-post.sh <sizeGiB> <nodeId> <commitmentAtxId>
#
## Author:
#
# Zanoryt <zanoryt@protonmail.com>
#

desiredSizeGiB=${1:-256}
desiredSizeBytes=$(($desiredSizeGiB * 1024 * 1024 * 1024))
nodeId=${2:-"511660323b54d3a5a06a1bcd1e9bedafcf4d9c1d88221c36628f19a9f671d2db"}
# id=$(echo "$nodeId" | base64 -d | xxd -p -c 32 -g 32)        # nodeId in HEX format
commitmentAtxId=${3:-"9eebff023abb17ccb775c602daade8ed708f0a50d3149a42801184f5b74f2865"}
numGpus=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
numGpus=$(($numGpus + 0)) # convert to int
labelsPerUnit="4294967296"                   # 2^32
maxFileSize="2147483648"                     # 2^31
numUnits=$(($desiredSizeGiB / 64))           # 64 GiB per unit
numUnits=$(($numUnits + 0))                  # convert to int

echo "Node ID         : ${nodeId}"
echo "CommitmentAtxId : ${commitmentAtxId}"
echo "Number of GPUs  : ${numGpus}"
echo "Desired size    : ${desiredSizeGiB} GiB"
echo "Labels per unit : ${labelsPerUnit}"
echo "Max file size   : ${maxFileSize}"
echo "Number of units : ${numUnits}"

PLOT_SPEED_URL="https://raw.githubusercontent.com/smeshcloud/smesher-plot-speed/main/smesher-plot-speed.py"
POSTCLI_VERSION="0.8.11"
POSTCLI_PATH="/tmp/postcli"
POSTCLI_FULLPATH="${POSTCLI_PATH}/postcli"
PLOT_SPEED_FULLPATH="/tmp/smesher-plot-speed.py"
POST_DATA_PATH="/tmp/post-data"

# Update system and install dependencies
apt update && apt install -y clinfo nvtop htop screen unzip xxd python3 tmux

# Download postcli
rm -rf $POSTCLI_PATH
mkdir -p $POSTCLI_PATH
wget -q -O postcli-Linux.zip https://github.com/spacemeshos/post/releases/download/v${POSTCLI_VERSION}/postcli-Linux.zip
unzip -u postcli-Linux.zip -d $POSTCLI_PATH
rm postcli-Linux.zip
chmod +x $POSTCLI_FULLPATH

wget -O $PLOT_SPEED_FULLPATH $PLOT_SPEED_URL

rm -rf $POST_DATA_PATH
mkdir -p $POST_DATA_PATH

numFiles=$($POSTCLI_FULLPATH -numUnits $numUnits -printNumFiles)
numFiles=$(($numFiles + 0)) # convert to int
numFilesPerGpu=$(($numFiles / $numGpus))
numFilesPerGpu=$(($numFilesPerGpu + 0)) # convert to int
echo "Number of files : ${numFiles}"
echo "Files per GPU   : ${numFilesPerGpu}"

echo "Initializing tmux"
tmux new-session -d -s post -n smesher-plot-speed
tmux send-keys -t post "watch -n 5 python3 $PLOT_SPEED_FULLPATH ${POST_DATA_PATH} --report" Enter
tmux new-window -t post -n nvtop
tmux send-keys -t post:nvtop "nvtop" Enter
tmux new-window -t post -n htop
tmux send-keys -t post:htop "htop" Enter

echo "Spawning tmux windows to generate post files..."
for ((i=1; i<=$numGpus; i++))
do
  provider=$((i-1))
  tmux new-window -a -t post -n post$provider
  fromFile=$(($numFilesPerGpu*$provider))
  toFile=$((-1+$numFilesPerGpu*$i))
  tmux send-keys -t post:post$provider "$POSTCLI_FULLPATH -provider $provider -commitmentAtxId $commitmentAtxId -id $nodeId -labelsPerUnit $labelsPerUnit -maxFileSize $maxFileSize -numUnits $numUnits -datadir $POST_DATA_PATH -fromFile $fromFile -toFile $toFile; exec bash" Enter
done

echo "Started generating the PoST data files."
echo ""
echo "To attach to the tmux session, run:"
echo ""
echo "  tmux attach-session -t post"
echo ""
echo "Have fun!"

# Sleep forever since things are running in the background
sleep infinity
