Calculate user agents and API calls in CI, based on a nightly Athena run.

```console
$ curl -s https://s3.amazonaws.com/aws-athena-query-results-460538899914-us-east-1/agents-and-events.csv | agents-and-events.py
765249  terraform:
        92791   ec2.DescribeNatGateways
        79912   ec2.CreateTags
        74594   ec2.DescribeSecurityGroups
        36770   ec2.DescribeImages
...
$ curl -s https://s3.amazonaws.com/aws-athena-query-results-460538899914-us-east-1/agents-and-events.csv | agents-and-events.py | grep '^[0-9]'
765249 terraform:
721717 destroyer:
...
```
