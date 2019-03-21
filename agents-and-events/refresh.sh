#!/bin/sh

DATE="$(date --iso=d --utc)" &&
curl -s https://s3.amazonaws.com/aws-athena-query-results-460538899914-us-east-1/agents-and-events.csv >"agents-and-events-${DATE}.csv" &&
./agents-and-events.py <"agents-and-events-${DATE}.csv" >"api-consumers-${DATE}.txt"
