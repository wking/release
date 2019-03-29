#!/usr/bin/python3
#
#   $ curl -s https://s3.amazonaws.com/aws-athena-query-results-460538899914-us-east-1/agents-and-events.csv | calls-per-vpc.py EVENT_NAME

import collections
import csv
import re
import sys


eventname = sys.argv[1]
agents = collections.defaultdict(lambda: collections.defaultdict(lambda: 0))
reader = csv.DictReader(sys.stdin)
for row in reader:
    agents[(row['username'], row['useragent'])][row['eventname']] += int(row['count'])

ratios = {}
for agent, events in agents.items():
    username = agent[0]
    if events['CreateVpc'] > 0:
        vpcs = events['CreateVpc']  # Terraform or other creator
    elif any(username.startswith(prefix) for prefix in ['ci-ln', 'ci-op', 'hive-']):
        vpcs = 1  # per-cluster user created by the cred operator
    else:
        continue
    ratios[agent] = events[eventname] / float(vpcs)

for agent, ratio in sorted(ratios.items(), key=lambda agent_ratio: (agent_ratio[1], agent_ratio[0])):
    if ratio == 0:
        continue
    print('{:.2f}\t{}\t{}\t{}\t{}'.format(ratio, agents[agent]['CreateVpc'], agents[agent][eventname], *agent))
