#!/usr/bin/env python3

import collections
import json
import urllib.request


with urllib.request.urlopen('https://prow.svc.ci.openshift.org/prowjobs.js') as response:
    data = response.read()
jobs = json.loads(data.decode('utf-8'))
state_counts = collections.defaultdict(lambda: collections.defaultdict(lambda: 0))
for job in jobs['items']:
    try:
        state_counts[job['spec']['job']][job.get('status', {}).get('state', 'unknown')] += 1
    except Exception:
        print(job)
        raise

rates = {}
for job, states in state_counts.items():
    success = states.get('success', 0)
    failure = states.get('failure', 0)
    done = success + failure
    if not done:
        continue
    rates[job] = {
        'total': sum(states.values()),
        'success': success,
        'failure': failure,
        'done': done,
        'rate': success / float(done),
    }

for job, rate in sorted(rates.items(), key=lambda job_rate: (-job_rate[1]['rate'], job_rate[1]['done'])):
    print('{rate:.2f} ({success}/{done}) {job}'.format(job=job, **rate))
