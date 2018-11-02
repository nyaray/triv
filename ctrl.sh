#!/usr/bin/env bash

echo "Triv command central"
echo

while :
do
    echo "e - exit"
    echo "c - clear"
    echo "n - new question"
    echo "a - test team foo"
    echo "b - test team bar"

    read -r -p "Command: " cmd

    case $cmd in
        e) break ;;
        c) curl -s localhost:8080/api -d '"clear"' ;;
        n) curl -s https://opentdb.com/api.php?amount=1 \
            | jq -c -M .results[0] \
            | curl -s -X POST localhost:8080/api -d @- ;;
        a) curl -s localhost:8080/api -d '{"team_token": "foo"}' ;;
        b) curl -s localhost:8080/api -d '{"team_token": "bar"}' ;;
        *) echo "Invalid choice"; echo
    esac

    echo
    echo

done
