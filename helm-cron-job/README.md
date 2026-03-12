The xlog checker github action is meant to run once an hour to ensure the GoldDR patroni databases remain in sync with their gold counterpart.

A cron job has been created to trigger this action every hour.

## Deployment

There is curently no pipeline for deploying this cron job.  It will be done from the local command line to the GoldDR production namespace.

- Create a secret `xlog-cron-job-secret` in the **GoldDR** eb75ad-tools namespace.
- Add the github github_token, repo, and owner to it.
- From a local terminal log into the **GoldDR** cluster
- Run `make upgrade`
