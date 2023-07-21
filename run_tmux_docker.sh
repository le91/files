#!/bin/bash
if tmux attach -t docker-0; then
    touch /root/run_tmux.sh
else
    tmux new-session -t docker
fi
