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


reader = csv.DictReader(sys.stdin)
requests = collections.defaultdict(list)
error_codes =  collections.defaultdict(lambda: 0)
creates = deletes = 0
begin = end = None
for row in reader:
    #if row['errorcode'] == 'Client.DependencyViolation':
    #    continue
    timestamp = datetime.datetime.strptime(row['eventtime'], '%Y-%m-%dT%H:%M:%SZ')
    #if timestamp < datetime.datetime(2019, 3, 2) or timestamp > datetime.datetime(2019, 3, 2, 4):
    #    continue
    if not begin:
        begin = timestamp
    end = timestamp
    actor = 'unknown'
    if 'OpenShift/4.x Destroyer' in row['useragent']:
        actor = 'destroyer'
    elif 'Terraform' in row['useragent']:
        actor = 'terraform'
    if row['errorcode']:
        actor += ' (error)'
        error_codes[row['errorcode']] += 1
    elif row['eventname'] == 'CreateVpc':
        creates += 1
    elif row['eventname'] == 'DeleteVpc':
        deletes += 1
    requests[actor].append(timestamp)
    requests['total'].append(timestamp)

data = []
names = []
colors = []
for i, (name, color) in enumerate([
        ('terraform', 'green'),
        ('destroyer', 'blue'),
        ('unknown', 'purple'),
        ]):
    if len(requests[name]) == 0:
        continue
    data.append(matplotlib.dates.date2num(requests[name]))
    names.append(name)
    colors.append(color)

locator = matplotlib.dates.AutoDateLocator()
figure = matplotlib.pyplot.figure()
figure.set_size_inches(20, 10)
axes = figure.add_subplot(2, 1, 1)
axes.hist(data, 288, histtype='barstacked', rwidth=1, edgecolor='none', color=colors, label=names)
axes.set_title('VPC creation and deletion (excluding errors, {} creates, {} deletes)'.format(creates, deletes))
axes.set_ylabel('stacked count (per 10-minute bin)')
axes.set_xlabel('{} through {} UTC'.format(begin.isoformat(' '), end.isoformat(' ')))
axes.legend(loc='upper left', frameon=False)
axes.xaxis.set_major_locator(locator)
axes.xaxis.set_major_formatter(matplotlib.dates.AutoDateFormatter(locator))
axes.axis('tight')

data = []
names = []
colors = []
for i, (name, color) in enumerate([
        ('terraform (error)', 'orange'),
        ('destroyer (error)', 'cyan'),
        ('unknown (error)', 'red'),
        ('terraform', 'green'),
        ('destroyer', 'blue'),
        ('unknown', 'purple'),
        ]):
    if len(requests[name]) == 0:
        continue
    data.append(matplotlib.dates.date2num(requests[name]))
    names.append(name)
    colors.append(color)

axes = figure.add_subplot(2, 1, 2)
axes.hist(data, 288, histtype='barstacked', rwidth=1, edgecolor='none', color=colors, label=names)
axes.set_title('VPC creation and deletion (including errors)')
axes.set_ylabel('stacked count (per 10-minute bin)')
axes.set_xlabel('{} through {} UTC'.format(begin.isoformat(' '), end.isoformat(' ')))
axes.legend(loc='upper left', frameon=False)
axes.xaxis.set_major_locator(locator)
axes.xaxis.set_major_formatter(matplotlib.dates.AutoDateFormatter(locator))
axes.axis('tight')

figure.tight_layout()
figure.autofmt_xdate()
figure.savefig('vpc.png')

for count, error_code in sorted([(count, error_code) for error_code, count in error_codes.items()]):
    print('{}\t{}'.format(count, error_code))
