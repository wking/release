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


#error_suffix = ' (error)'
error_suffix = None
yscale = 'log'
errors = set()
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
        if error_suffix:
            event += error_suffix
        else:
            event += ' ({})'.format(row['errorcode'])
        errors.add(event)
    requests[event].append(timestamp)

data = []
names = []
for event, times in sorted(requests.items()):
    if event in errors:
        continue
    data.append(matplotlib.dates.date2num(times))
    names.append(event)
for event, times in sorted(requests.items()):
    if event not in errors:
        continue
    data.append(matplotlib.dates.date2num(times))
    names.append(event)

bin_minutes = 120
bins = int((end - begin).total_seconds()) // (60 * bin_minutes)
locator = matplotlib.dates.AutoDateLocator()
figure = matplotlib.pyplot.figure()
figure.set_size_inches(20, 10)

axes = figure.add_subplot(2, 1, 1)
if yscale:
    axes.set_yscale(yscale)
_, bins, _ = axes.hist(data, bins, histtype='barstacked', rwidth=1, edgecolor='none', label=names)
axes.set_title('Calls')
axes.set_xlabel('{} through {} UTC'.format(begin.isoformat(' '), end.isoformat(' ')))
axes.set_ylabel('stacked count (per {}-minute bin)'.format(bin_minutes))
axes.legend(loc='upper left', frameon=False)
axes.xaxis.set_major_locator(locator)
axes.xaxis.set_major_formatter(matplotlib.dates.AutoDateFormatter(locator))
axes.axis('tight')

def num2date(num):  # not in my ancient Matplotlib v1.2.0's matplotlib.dates
    return begin + datetime.timedelta(days=num - bins[0])

bin_centers = [(a + b) / 2 for a, b in zip(bins, bins[1:])]
counts = collections.defaultdict(list)
for name in names:
    for i in range(len(bin_centers)):
        b = num2date(bins[i])
        e = num2date(bins[i+1])
        counts[name].append(len([t for t in requests[name] if t >= b and t <= e]))
vpc_counts = float(len(requests['CreateVpc']))

xs = []
ys = []
new_names = []
for name in names:
    print('{}\t{:.2f}\t{}'.format(len(requests[name]), len(requests[name]) / vpc_counts, name))
    if name == 'CreateVpc':
        continue
    xs.append(bin_centers)
    ys.append([count / float(vpc_count) for count, vpc_count in zip(counts[name], counts['CreateVpc'])])
    new_names.append(name)

axes = figure.add_subplot(2, 1, 2)
if yscale:
    axes.set_yscale(yscale)
for x, y, name in zip(xs, ys, new_names):
    axes.plot(x, y, label=name)
axes.set_xlabel('{} through {} UTC'.format(begin.isoformat(' '), end.isoformat(' ')))
axes.set_ylabel('count (per {}-minute bin, per VPC)'.format(bin_minutes))
axes.legend(loc='upper left', frameon=False)
axes.xaxis.set_major_locator(locator)
axes.xaxis.set_major_formatter(matplotlib.dates.AutoDateFormatter(locator))
axes.axis('tight')
axes.set_xlim(bins[0], bins[-1])

figure.savefig('calls-per-vpc.png')
