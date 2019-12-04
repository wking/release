#!/usr/bin/env python3

import argparse
import collections
import datetime
import json
import re
import urllib.parse
import urllib.request


parser = argparse.ArgumentParser(description='Summarize Prow job success by job name.')
parser.add_argument(
    '-v', '--verbose', action='store_const', const=True, default=False,
    help='Verbose output (e.g. print URIs for failing jobs).')
parser.add_argument(
    '-j', '--include-job',
    help='Only include jobs whose name matches the provided regular expression.')
parser.add_argument(
    '-s', '--since',
    help='Filter to jobs with startTime greater than or equal to this value (YYYY-MM-DDTHH:MM:SSZ).')
parser.add_argument(
    '-b', '--exclude-build-log',
    help='Exclude failures whose build log matches the provided regular expression.')

args = parser.parse_args()

with urllib.request.urlopen('https://prow.svc.ci.openshift.org/prowjobs.js') as response:
    data = response.read()
jobs = json.loads(data.decode('utf-8'))

if args.include_job:
    regex = re.compile(args.include_job)
    jobs['items'] = [
        job for job in jobs['items']
        if regex.match(job['spec']['job'])
    ]


if args.since:
    since = datetime.datetime.strptime(args.since, '%Y-%m-%dT%H:%M:%SZ')
    jobs['items'] = [
        job for job in jobs['items']
        if datetime.datetime.strptime(job.get('status', {}).get('startTime') or '1900-01-01T00:00:00Z', '%Y-%m-%dT%H:%M:%SZ') >= since
    ]

excluded = set()
if args.exclude_build_log:
    params = {
        'name': '.',
        'maxAge': '24h',
        'context': '0',
        'type': 'build-log',
        'search': args.exclude_build_log,
    }
    if args.include_job:
        params['name'] = args.include_job
    uri = 'https://search.svc.ci.openshift.org/search?{}'.format(urllib.parse.urlencode(params))
    with urllib.request.urlopen(uri) as response:
        data = response.read()
    excluded = json.loads(data.decode('utf-8'))
    #print('{}\n  {}'.format(uri, '\n  '.join(excluded.keys())))
    jobs['items'] = [
        job for job in jobs['items']
        if job.get('status', {}).get('url') not in excluded
    ]

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
    suffix = ''
    if args.verbose:
        uris = [
            j.get('status', {}).get('url')
            for j in jobs['items']
            if j['spec']['job'] == job and j.get('status', {}).get('state') == 'failure'
        ]
        uris = [uri for uri in uris if uri]  # remove empty strings
        if len(uris) > 2:
            uris = uris[:2] + ['...']
        if uris:
            suffix = ' {}'.format(' '.join(uris))
    print('{rate:.2f} ({success}/{done}) {job}{suffix}'.format(job=job, suffix=suffix, **rate))
