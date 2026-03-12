# Uptime Checker API

This app will run a browser automation check of the health of the keycloak application and change the status of the API from 200 to 500(VERIFY THIS) for the status cake application to monitor.

Location: hosted in the Gold Cluster.  If the Gold Cluster is down we want status cake to return an alert regardless.


## Deployment

### Build the image

In the uptime checker folder build the image:

```
docker build . -t ghcr.io/bcgov/sso-uptime-monitor:dev
```

and push it to the bcgov ghcr repos.

```
docker push ghcr.io/bcgov/sso-uptime-monitor:dev
```

### Run the make command

```make upgrade```
