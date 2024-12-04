# Generating service accounts for the CICD pipeline

The github actions need service accounts to run. The script `generate_sa.sh` will create a service acount for the prod environment of a given openshift project and give that account the roles in the dev, test, and prod environments for deploying the keycloak site.

## Generate the service accounts

While logged into the **Gold** instance run:

`
./generate_sa.sh <<LICENCE_PLATE>> gold
`

The service account, roles, and rolebindings will be created.

Log into the **GoldDR** cluster and repeat the same command.

`
./generate_sa.sh <<LICENCE_PLATE>> golddr
`

## Update the github action secrets

The github actions rwquire 4 secrets to deploy resources in Gold and GoldDR.

Each service account will generate a secret in the `-prod` namespace with the name `sso-action-deployer-<<LICENCE_PLATE>>-token-#####`.  Copy this token into the GithHub secrets on this repos.

OPENSHIFT_TOKEN_GOLD_SANDBOX
OPENSHIFT_TOKEN_GOLDDR_SANDBOX
OPENSHIFT_TOKEN_GOLD_PRODUCTION
OPENSHIFT_TOKEN_GOLDDR_PRODUCTION
