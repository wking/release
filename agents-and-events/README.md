Calculate user agents and API calls in CI, based on a nightly Athena run.

```console
$ curl -s https://s3.amazonaws.com/aws-athena-query-results-460538899914-us-east-1/agents-and-events.csv | agents-and-events.py
888821 cloud-credential-operator:
       830510    iam.GetUser (NoSuchEntityException)
       20025     iam.CreateAccessKey
       17548     iam.DeleteAccessKey
       4194      iam.GetUser
...
$ curl -s https://s3.amazonaws.com/aws-athena-query-results-460538899914-us-east-1/agents-and-events.csv | agents-and-events.py | grep '^[0-9]'
888821 cloud-credential-operator:
469000 terraform:
...
```

You can also generate the calls per-VPC (i.e. per-cluster) for a given API endpoint:

```console
$ curl -s https://s3.amazonaws.com/aws-athena-query-results-460538899914-us-east-1/agents-and-events.csv | calls-per-vpc.py ChangeResourceRecordSets
2.00  0  2   ci-ln-2jx9ht2-703b0-openshift-ingress-2lzh7    aws-sdk-go/1.15.72 (go1.10.3; linux; amd64) openshift.io ingress-operator/4.0.0-0.ci-2019-03-28-094213
2.00  0  2   ci-ln-6kj2hq2-703b0-openshift-ingress-xfx64    aws-sdk-go/1.15.72 (go1.10.3; linux; amd64) openshift.io ingress-operator/4.0.0-0.ci-2019-03-28-064631
...
6.00  0  6   ci-op-wv27t0cf-43abb-openshift-ingress-4ts5m   aws-sdk-go/1.15.72 (go1.10.3; linux; amd64) openshift.io ingress-operator/0.0.1-2019-03-28-140915
6.00  0  6   ci-op-yhklktk9-0ffca-openshift-ingress-znrv6   aws-sdk-go/1.15.72 (go1.10.3; linux; amd64) openshift.io ingress-operator/4.0.0-0.ci-2019-03-28-054530
6.00  1  6   origin-ci-robot-provision                      aws-sdk-go/1.17.11 (go1.10.8; linux; amd64) APN/1.0 HashiCorp/1.0 Terraform/0.11.10
```

The Lambda function feeding `agents-and-events.csv` is based on [`report-agents-and-events.py`](report-agents-and-events.py).
