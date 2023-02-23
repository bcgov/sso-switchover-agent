# Local developement guide for the switchover agent.

## Publishing the agent to a specific environment

Due to the agent working in the openshift cluster, a purely local developement environment may not be feasible.  However it is still useful to be able to build the app locally and deploy it to a sandbox environment.

### Creating the github image locally.

```
docker build . -t switchagent:testtag
```

### Publishing the image to a remote repos

Publishing the imgage to the sso-switchover-agent repos requires three steps:

1) Tagging the local image:
<!-- # docker tag [OPTIONS] IMAGE[:TAG] [REGISTRYHOST/][USERNAME/]NAME[:TAG] -->
```
docker tag switchagent:testtag ghcr.io/bcgov/sso-switchover-agent:testtag
```

2) Login to the ghcr here is a [github guide](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)

3) Pushing the repos up:
```
docker push ghcr.io/bcgov/sso-switchover-agent:testtag
```

### Deploying the image to a specific namespace.

This imgage can be deployed from the local environment using helm. Note you must be logged into the GoldDR cluster for this, not the gold cluster.

```
helm upgrade --install <<test-deployment-name>> . \
-n <<namespace>> \
-f values.yaml \
-f "values-c6af30-local.yaml"
```
