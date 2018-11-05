#!/usr/bin/env bash

echo "Triv command central"
echo

while :
do
    echo "e - exit"
    echo "c - clear"
    echo "n - new question"
    echo "1 - test team foo"
    echo "2 - test team bar"
    echo "3 - test team baz"

    read -r -p "Command: " cmd

    case $cmd in
        e) break ;;
        c) curl -s localhost:8080/api -d '"clear"' ;;
        n) curl -s https://opentdb.com/api.php?amount=1 \
            | jq -c -M .results[0] \
            | curl -s -X POST localhost:8080/api -d @- ;;
        1) curl -s localhost:8080/api -d '{"team_token": "foo"}' ;;
        2) curl -s localhost:8080/api -d '{"team_token": "bar"}' ;;
        3) curl -s localhost:8080/api -d '{"team_token": "baz"}' ;;
        *) echo "Invalid choice"; echo
    esac

    echo
    echo

done
