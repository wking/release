#!/bin/sh
#
# Make sure the commands we have in the README produce the SVGs we have in version control ;)

curl -s https://storage.googleapis.com/origin-ci-test/logs/release-openshift-origin-installer-e2e-aws-4.0/6016/artifacts/e2e-aws/installer/.openshift_install.log | ./terraform-waterfall.py >terraform.svg
curl -s https://storage.googleapis.com/origin-ci-test/logs/release-openshift-origin-installer-e2e-aws-4.0/6016/artifacts/e2e-aws/pods/openshift-cluster-version_cluster-version-operator-74d8d99566-2bh4q_cluster-version-operator.log.gz | gunzip | ./cvo-waterfall.py >cvo.svg
