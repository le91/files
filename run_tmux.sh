#!/bin/bash
if tmux attach -t main-0; then
    touch /home/oracle/run_tmux.sh
else
    tmux new-session -t main
fi
