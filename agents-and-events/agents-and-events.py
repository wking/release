#!/usr/bin/python3
#
#   $ curl -s https://s3.amazonaws.com/aws-athena-query-results-460538899914-us-east-1/agents-and-events.csv | agents-and-events.py

import collections
import csv
import re
import sys


humans = set([
    'acrawfor',
    'ccoleman',
    'jolamb',
    'jrussell',
    'dmace',
    'trking',
])

boring_users = set([
    '',
#    'origin-ci-robot-provision',
])

username_regexp = re.compile('^(?:ci-(?:op|ln)|[a-z0-9]*)-[a-z0-9]*-[a-z0-9]*-([a-z-]*)-[a-z0-9]*$')
service_regexp = re.compile('^([^-]*)\.amazonaws\.com$')
unrecognized_user_agents = set()
operator_actions = collections.defaultdict(lambda: collections.defaultdict(lambda: 0))
reader = csv.DictReader(sys.stdin)
for row in reader:
    username = row['username']
    match = username_regexp.match(username)
    operator = None
    if match:
        operator = match.group(1)
    elif 'Ansible' in row['useragent']:
        operator = 'ansible'
    elif 'athena.amazonaws.com' in row['useragent']:
        operator = 'aws-athena'
    elif 'autoscaling.amazonaws.com' in row['useragent']:
        operator = 'aws-autoscaling'
    elif 'AWS Internal' in row['useragent']:
        operator = 'aws-internal'
    elif 'AWS_Lambda' in row['useragent'] or 'awslambda-worker' in row['useragent'] or 'lambda.amazonaws.com' in row['useragent']:
        operator = 'aws-lambda'
    elif 'cloud-credential-operator' in row['useragent']:
        operator = 'cloud-credential-operator'
    elif 'cluster-api-provider-aws/dummy' in row['useragent']:
        operator = 'cluster-api-provider-aws/dummy'
    elif 'ec2.amazonaws.com' in row['useragent'] or 'ec2-frontend-api.amazonaws.com' in row['useragent']:
        operator = 'aws-ec2'
    elif 'elasticloadbalancing.amazonaws.com' in row['useragent']:
        operator = 'aws-elasticloadbalancing'
    elif 'OpenShift/4.x Installer' in row['useragent']:
        operator = 'installer'
    elif 'OpenShift/4.x Destroyer' in row['useragent']:
        operator = 'destroyer'
    elif 'openshift-image-registry' in username:
        operator = 'openshift-image-registry'
    elif 'openshift-ingress' in username:
        operator = 'openshift-ingress'
    elif 'Terraform/' in row['useragent']:
        operator = 'terraform'
    elif username in boring_users:
        operator = row['useragent'].split(' ', 2)[0]
        unrecognized_user_agents.add(row['useragent'])
    else:
        operator = username

    if operator in humans:
        continue
    if '49671d7b-6bd0-4728-cloud-credential-operator-iam-ro-82djx' in row['username']:  # example of pulling out a specific CI user
        operator = '49671d7b-6bd0-4728-cloud-credential-operator-iam-ro-82djx'

    service = None
    match = service_regexp.match(row['eventsource'])
    if match:
        service = match.group(1)
    else:
        raise ValueError('unrecognized event source: {!r}'.format(row['eventsource']))
    event = '{}.{}'.format(service, row['eventname'])
    if row.get('errorcode', ''):
        event += ' ({})'.format(row['errorcode'])
    operator_actions[operator][event] += int(row['count'])

for operator, actions in operator_actions.items():
    actions['total'] = sum(actions.values())

for operator, actions in sorted(
        operator_actions.items(),
        key=lambda operator_actions: operator_actions[1]['total'],
        reverse=True):
    print('{}\t{}:'.format(actions.pop('total'), operator))
    for event, count in sorted(
            actions.items(),
            key=lambda event_count: event_count[1],
            reverse=True):
        print('\t{}\t{}'.format(count, event))

print('\nunrecognized user-agents:')
print('\n'.join(sorted(unrecognized_user_agents)))
