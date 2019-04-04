Scripts for pulling and grepping Deck builds logs.
This makes it easier to estimate the impact of a given error in OpenShift CI.
First, populate your local cache of build logs (`~/.cache/openshift-deck-build-logs`) from recent failing `*-e2e-aws*` jobs:

```console
$ deck-build-log-pull
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 7250k    0 7250k    0     0  2612k      0 --:--:--  0:00:02 --:--:-- 2611k
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  2014  100  2014    0     0   4129      0 --:--:-- --:--:-- --:--:--  4135
...
```

This seems to pull 48 hours of failures, so the first run will take a while.
Subsequent `deck-build-log-pull` calls will fetch the list of recent jobs, but will then only download build logs from new failures (and prune older failures), so they'll be faster if you're polling throughout the day.

Then search the logs for a given error message:

```console
$ deck-build-log-grep 'Error launching source instance'
Error launching source instance matches 29 of 625 failures
.../.cache/openshift-deck-build-logs/pr-logs/pull/operator-framework_operator-lifecycle-manager/777/pull-ci-operator-framework-operator-lifecycle-manager-master-e2e-aws-olm/1364/build-log.txt:2
.../.cache/openshift-deck-build-logs/pr-logs/pull/operator-framework_operator-lifecycle-manager/777/pull-ci-operator-framework-operator-lifecycle-manager-master-e2e-aws-olm/1365/build-log.txt:2
...
```

To plot matching failures over time, you can use:

```console
$ deck-build-log-plot 'Error launching source instance' 'aws_route_table_association.*timeout while waiting for state' 'aws_route\..*timeout while waiting for state'
```

which produces both PNG and SVG output like:

![](deck-build-log.png)

Viewing the SVG output in your browser allows you to use the markers as hyperlinks to the job's build page. 

There are `FIXME` markers in `deck-build-log-plot` in case you want to alter it to perform a different analysis.

To get a quick estimate of failure rates over the whole set of cached logs, use:

```console
$ deck-build-log-hot | head -n4
$ ./deck-build-log-hot | head -n4
Failed  % of 112        Test (started between 2019-04-03T08:27:36 and 2019-04-04T02:32:49 UTC)
41      36      [Disruptive] Cluster upgrade should maintain a functioning cluster [Feature:ClusterUpgrade] [Suite:openshift] [Serial]
31      27      [Feature:Platform] Managed cluster should have no crashlooping pods in core namespaces over two minutes [Suite:openshift/conformance/parallel]
9       8       [sig-scheduling] ResourceQuota should create a ResourceQuota and capture the life of a secret. [Suite:openshift/conformance/parallel] [Suite:k8s]
```
