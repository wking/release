#!/usr/bin/python2
#
# Crunch the CSV output from:
#
#   SELECT eventtime,
#          eventname,
#          useridentity.username,
#          useragent,
#          errorcode,
#          errormessage
#   FROM "default"."cloudtrail_logs_cloud_trail_test_clayton"
#   WHERE from_iso8601_timestamp(eventtime) > date_add('hour', -48, now())
#     AND eventname IN ('CreateVpc', 'DeleteVpc')
#   ORDER BY eventtime;
#
# with:
#
#   $ ./vpc.py <vpc.csv

import collections
import csv
import datetime
import sys

import matplotlib.dates
import matplotlib.pyplot


error_suffix = ' (error)'
reader = csv.DictReader(sys.stdin)
requests = collections.defaultdict(list)
creates = deletes = 0
begin = end = None
for row in reader:
    timestamp = datetime.datetime.strptime(row['eventtime'], '%Y-%m-%dT%H:%M:%SZ')
    #if timestamp < datetime.datetime(2019, 3, 2) or timestamp > datetime.datetime(2019, 3, 2, 4):
    #    continue
    if not begin:
        begin = timestamp
    end = timestamp
    event = row['eventname']
    if row['errorcode']:
        event += error_suffix
    requests[event].append(timestamp)

data = []
names = []
for event, times in sorted(requests.items()):
    if not event.endswith(error_suffix):
        continue
    data.append(matplotlib.dates.date2num(times))
    names.append(event)
for event, times in sorted(requests.items()):
    if event.endswith(error_suffix):
        continue
    data.append(matplotlib.dates.date2num(times))
    names.append(event)

bin_minutes = 120
bins = int((end - begin).total_seconds()) // (60 * bin_minutes)
locator = matplotlib.dates.AutoDateLocator()
figure = matplotlib.pyplot.figure()
figure.set_size_inches(20, 10)

axes = figure.add_subplot(2, 1, 1)
n, bins, _ = axes.hist(data, bins, histtype='barstacked', rwidth=1, edgecolor='none', label=names)
axes.set_title('Calls')
axes.set_xlabel('{} through {} UTC'.format(begin.isoformat(' '), end.isoformat(' ')))
axes.set_ylabel('stacked count (per {}-minute bin)'.format(bin_minutes))
axes.legend(loc='upper left', frameon=False)
axes.xaxis.set_major_locator(locator)
axes.xaxis.set_major_formatter(matplotlib.dates.AutoDateFormatter(locator))
axes.axis('tight')

vpc_index = names.index('CreateVpc')
if vpc_index < 0:
    raise ValueError(names)
vpc_counts = n[vpc_index]
xs = []
ys = []
for counts, name in zip(n, names):
    if name == 'CreateVpc':
        continue
    xs.append([(a + b) / 2 for a, b in zip(bins, bins[1:])])
    ys.append([count / (float(vpc_count) or 1) for count, vpc_count in zip(counts, vpc_counts)])

axes = figure.add_subplot(2, 1, 2)
for x, y, name in zip(xs, ys, names):
    axes.plot(x, y, label=name)
axes.set_xlabel('{} through {} UTC'.format(begin.isoformat(' '), end.isoformat(' ')))
axes.set_ylabel('count (per {}-minute bin, per VPC)'.format(bin_minutes))
axes.legend(loc='upper left', frameon=False)
axes.xaxis.set_major_locator(locator)
axes.xaxis.set_major_formatter(matplotlib.dates.AutoDateFormatter(locator))
axes.axis('tight')
axes.set_xlim(bins[0], bins[-1])

figure.savefig('calls-per-vpc.png')

vpc_count = float(sum(vpc_counts))
for counts, name in zip(n, names):
    print('{}\t{:.2f}\t{}'.format(sum(counts), sum(counts) / vpc_count, name))
