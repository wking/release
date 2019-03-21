#!/usr/bin/python3
#
#   $ curl -s https://storage.googleapis.com/origin-ci-test/logs/release-openshift-origin-installer-e2e-aws-4.0/6016/artifacts/e2e-aws/installer/.openshift_install.log | terraform-waterfall.py >terraform.svg

import datetime
import re
import sys


log_regexp = re.compile('^time="([0-9T:-]*)Z" level=([a-z]*) msg="([^"]*)".*$')
creating_regexp = re.compile('^([^:]*): Creating\.\.\.$')
created_regexp = re.compile('^([^:]*): Creation complete after .*$')

resources = {}
reference_time = None
for line in sys.stdin.readlines():
    match = log_regexp.match(line)
    if not match:
        continue
    time, _, message = match.groups()
    timestamp = datetime.datetime.strptime(time, '%Y-%m-%dT%H:%M:%S')  # fromisoformat is new in Python 3.7

    match = creating_regexp.match(message)
    if match:
        if reference_time is None:
            reference_time = timestamp
        resources[match.group(1)] = [timestamp]
        continue

    match = created_regexp.match(message)
    if not match:
        continue

    resources[match.group(1)].append(timestamp)

rectangles = []
y = 0
step = 4
for resource, (start_time, stop_time) in sorted(resources.items(), key=lambda resource_times: resource_times[1][0]):
    start = (start_time - reference_time).total_seconds()
    stop = (stop_time - reference_time).total_seconds()
    rectangles.append('<rect x="{}" y="{}" width="{}" height="{}" fill="blue"><title>{} ({})</title></rect>'.format(start, y, stop - start, step, resource, stop_time - start_time))
    y += step

print('<svg viewBox="0 0 {} {}" xmlns="http://www.w3.org/2000/svg">'.format(stop, y)) 
for rectangle in rectangles:
    print('  {}'.format(rectangle))
print('</svg>')
