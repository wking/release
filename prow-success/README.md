[`prow-success.py`](prow-success.py) is a Python script to return a ranked list of OpenShift jobs sorted by success rate (decreasing) with ties broken by completed-job count (increasing).
That puts the jobs that fail the most at the bottom of the output, with ties broken by better statistics being lower in the output, so get worried about the tail of the output.
For example:

```console
$ prow-success.py
1.00 (1/1) branch-ci-openshift-oc-release-4.4-images
1.00 (1/1) branch-ci-codeready-toolchain-toolchain-common-master-test
1.00 (1/1) periodic-label-sync
...
1.00 (240/240) periodic-ipi-deprovision
0.99 (67/68) pull-ci-openshift-release-master-core-dry
..
0.00 (0/133) periodic-ci-openshift-osde2e-master-e2e-int-4.2-4.3
0.00 (0/142) periodic-ci-openshift-osde2e-master-e2e-stage-4.2-4.2
```
