#!/usr/bin/python2

import datetime
import json
import re
try:
    import statistics
except ImportError:  # Python 2
    class statistics(object):
        @staticmethod
        def mean(data):
            return sum(data) / float(len(data))

        @staticmethod
        def median(median):
            values = sorted(median)
            index = len(values) // 2
            return values[index]
import urllib2

import matplotlib.dates
import matplotlib.pyplot


start_regexp = re.compile('^([0-9/: ]*) Running pod (release-)?e2e-aws\n$')
complete_regexp = re.compile('^([0-9/: ]*) Container setup in pod (release-)?e2e-aws completed successfully\n$')

class DateTimeEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, datetime.datetime):
            return {
                "_type": "datetime",
                "value": obj.isoformat(),
            }
        return super(DateTimeEncoder, self).default(obj)


class DateTimeDecoder(json.JSONDecoder):
    def __init__(self, *args, **kwargs):
        json.JSONDecoder.__init__(self, object_hook=self.object_hook, *args, **kwargs)

    def object_hook(self, obj):
        if '_type' not in obj:
            return obj
        type = obj['_type']
        if type == 'datetime':
            return datetime.datetime.strptime(obj['value'], '%Y-%m-%dT%H:%M:%S')
        return obj


data = {
    'success': [],
    'failure': [],
    'missing': [],
}

known_jobs = set()
try:
    with open('create-cluster.json') as f:
        data = json.load(f, cls=DateTimeDecoder)
        known_jobs.update([(name, job) for _, _, name, job in data['success']])
        known_jobs.update([(name, job) for _, name, job in data['failure']])
        known_jobs.update([(name, job) for name, job in data['missing']])
except IOError:
    pass

name = 'release-openshift-origin-installer-e2e-aws-4.1'
job = 0  # earlier runs have a different log format
while True:
    job += 1
    if (name, job) in known_jobs:
        continue
    print(job)
    uri = 'https://storage.googleapis.com/origin-ci-test/logs/{}/{}/build-log.txt'.format(name, job)
    try:
        response = urllib2.urlopen(url=uri)
    except urllib2.HTTPError as error:
        if job < 671:  # known recent job, you may want to bump this
            data['missing'].append((name, job))
            continue
        print(error)
        break
    start = complete = None
    for line in response.readlines():
        if start is None:
            match = start_regexp.match(line)
            if match:
                start = datetime.datetime.strptime(match.group(1), '%Y/%m/%d %H:%M:%S')
        match = complete_regexp.match(line)
        if match:
            complete = datetime.datetime.strptime(match.group(1), '%Y/%m/%d %H:%M:%S')
            break
    response.close()
    if complete is not None:
        data['success'].append([start, complete, name, job])
    elif start is not None:
        data['failure'].append([start, name, job])
    else:
        data['missing'].append([name, job])

for data_list in data.values():
    data_list.sort()

with open('create-cluster.json', 'w') as f:
    json.dump(data, f, cls=DateTimeEncoder, indent=2, sort_keys=True)

figure = matplotlib.pyplot.figure()
figure.set_size_inches(20, 5)
axes = figure.add_subplot(1, 1, 1)
axes.set_title('openshift-install create cluster')
axes.set_ylabel('time to success (minutes)')
axes.set_xlabel('start time')

xs = []
ys = []
urls = []
for start, complete, name, job in data['success']:
    xs.append(start)
    ys.append((complete - start).total_seconds() / 60.)
    urls.append('https://prow.k8s.io/view/gcs/origin-ci-test/logs/{}/{}'.format(name, job))
print('mean of last 50: {:.2f}'.format(statistics.mean(ys[-50:])))
print('median of last 50: {:.2f}'.format(statistics.median(ys[-50:])))

scatter = axes.scatter(x=xs, y=ys, marker='.', edgecolor='')
scatter.set_urls(urls)

locator = matplotlib.dates.MonthLocator()
axes.xaxis.set_major_locator(locator)
axes.xaxis.set_major_formatter(matplotlib.dates.AutoDateFormatter(locator))
axes.set_xlim(xs[0], xs[-1])
axes.set_ylim(0, max(ys))
figure.tight_layout()
#figure.autofmt_xdate()  # we don't have so many months that slanting them is useful
figure.savefig('create-cluster.png')
figure.savefig('create-cluster.svg')
