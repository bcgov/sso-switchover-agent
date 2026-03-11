# The trigger for the xlog checker job

Due to PATs needing to be renewed every 3 months for Github we are triggering the xlog checker using this small python image.

Build the imgage locally:

```
docker build . -t ghcr.io/bcgov/sso-xlog-trigger:production
```

Push to the github repo:

```
docker push ghcr.io/bcgov/sso-xlog-trigger:production
```
