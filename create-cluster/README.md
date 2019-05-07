Cluster creation time, by pattern matching in build logs for the [the origin release-promotion jobs][origin-release].
Run:

```console
$ create-cluster.py
...
mean of last 50: 31.74
median of last 50: 29.73
```

to produce both PNG and SVG output with the duration of the `setup` container:

![](create-cluster.png)

Viewing the SVG output in your browser allows you to use the markers as hyperlinks to the job's build page.

[origin-release]: https://origin-release.svc.ci.openshift.org/
