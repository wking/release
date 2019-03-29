#!/usr/bin/python2
#
# Plot concurrent clusters based on data from https://prow.svc.ci.openshift.org/data.js
#
#   $ ./concurrent.py

import collections
import datetime
import urllib2
import json
import os
import sys

import matplotlib.dates
import matplotlib.pyplot


def start_stop(job):
    start = datetime.datetime.utcfromtimestamp(int(job['started']))
    stop = None
    if job.get('finished', ''):
        stop = datetime.datetime.strptime(job['finished'], '%Y-%m-%dT%H:%M:%SZ')  # fromisoformat is new in Python 3.7
    return (start, stop)


response = urllib2.urlopen('https://prow.svc.ci.openshift.org/data.js')
jobs = json.load(response)
response.close()

clusters = []
for job in jobs:
    if '-e2e-aws' not in job['job']:
        continue
    start, stop = start_stop(job)
    clusters.append((start, stop))
clusters.sort(key=lambda start_stop: start_stop[0])

start = min(start for start, _ in clusters)
stop = max(stop for _, stop in clusters if stop is not None)

times = []
concurrent = []
time = start
while time < stop:
    times.append(time)
    concurrent.append(len([begin for begin, end in clusters if begin < time and (end is None or end > time)]))
    time += datetime.timedelta(minutes=5)

figure = matplotlib.pyplot.figure()
figure.set_size_inches(20, 5)

axes = figure.add_subplot(1, 1, 1)
axes.plot(times, concurrent, '.')
axes.set_title('Concurrent clusters')
axes.set_ylabel('count')
axes.set_xlabel('{} through {} UTC'.format(start.isoformat(' '), stop.isoformat(' ')))
locator = matplotlib.dates.AutoDateLocator()
axes.xaxis.set_major_locator(locator)
axes.xaxis.set_major_formatter(matplotlib.dates.AutoDateFormatter(locator))
axes.axis('tight')

figure.savefig('concurrent.png')
