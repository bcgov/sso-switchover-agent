# Local developement guide for the switchover agent.

## Publishing the agent to a specific environment

Due to the agent working in the openshift cluster, a purely local developement environment may not be feasible.  However it is still useful to be able to build the app locally and deploy it to a sandbox environment.

### Build and tag the github image locally.

```
docker build . -t ghcr.io/bcgov/sso-switchover-agent:testtag
```

### Publishing the image to a remote repos

Publishing the taged image to the sso-switchover-agent repos requires two steps:

1) Login to the ghcr, a guide can be found here: [github guide](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)

1) Pushing the repos up:
```
docker push ghcr.io/bcgov/sso-switchover-agent:testtag
```

### Deploying the image to a specific namespace.

This image can be deployed from the local environment using helm. Note you must be logged into the GoldDR cluster for this, not the gold cluster.

```
helm upgrade --install <<test-deployment-name>> . \
-n <<namespace>> \
-f values.yaml \
-f "values-c6af30-local.yaml"
```

### Configuring the openshift environment

In the gold dr namespace create the `sso-switchover-agent` secret, and configer the relevant environment variables. See [Environment Variables Documentation](./environment-variables.md).

## Running the local image:

For some development tasks, a deployment of the image to the gold dr cluster may not be neccessary.  In that case simply build and run the imagege locally:

```
docker build . -t <image_name>:<image_tag>
docker run <image_name>:<image_tag>
```

## Running unit tests:

The switchover agent tests can be run using the command:

```
poetry run pytest src/tests/trigger_test.py
```

In the root of the project.

## Running the queu tests

The queu tests run automatically on pr creation.  To run them locally:

```
docker build -f Dockerfile-test . -t switchover-test
docker run switchover-test
```

The docker container should raise no errors and terminate when the test is complete.
