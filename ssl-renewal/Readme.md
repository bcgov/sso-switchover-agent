# The SSL Cert renewal process.

## Steps
 - Create the myservice request for a new cert
 - Generate the cert singing request in the `./env/<<namepace>>/` folder. Submit to myservice and wait for certificates to be issued.
 - Run the bash script `update_route_credentials.sh` to upgrade the certs.

## Create the iStore Request for a new cert

You will need to complete the request form: https://ssbc-client.gov.bc.ca/services/isr_forms/hosting_ssl_site_reverse.docx

The form is submitted through the iStore by attaching it to a new ticket. https://imbsd.gov.bc.ca/.  You will need to be connected to the VPN to access this site.

## Generate the cert singing request in the `./env/<<namepace>>/` folder.

<!--  TODO CONVERT THIS CREATION TO A BASH SCRIPT -->
There will be five secrets uploaded to the namespace:

```
TLSChain.txt
TLSRoot.txt
TrustedRoot.txt
loginproxy.csr
loginproxy.key
<<url>>.txt
```

They can be stored locally in the untracked folders `./env/<<namepace>>/`.  Once the certs are generated, they can can be used by the `update_route_credentials.sh` script to update the Route objects.

**Note:** In certain cases a single cert is used for multiple environments.  In that case a copy of the secrets must be saved in each environment's namespace folder, and the `<<url>>.txt`, file must be renamed to vanity url used in that environment e.g. dev.loginproxy.gov.bc.ca.txt, test.loginproxy.gov.bc.ca.txt, dev.sandbox.loginproxy.gov.bc.ca.txt,tes.sandbox.loginproxy.gov.bc.ca.txt.


## Run the script to update the cert values

### GoldDR
In GoldDR, run:

`./update_route_credentials.sh <<namespace>> golddr year`

This script will create a secret with name `loginproxy-ssl-cert-secret.<<year>>` in the GoldDR namespace.  It will error out if a secret with that name already exists.

The certificate may not update imediately.  To check that the cert expiry date has updated, run the folowing script:

`./check_endpoint_health.sh <<namespace>> golddr`

The last line of output will be the date the certificate expires on.  It should be approximately 1 year in the future.

### Gold

Once the GoldDR route is confimed up and healthy, log into the Gold cluster and run:

`./update_route_credentials.sh <<namespace>> gold year`

Check that the Gold cert change worked by navigating to the browser. Or by running:

`./check_endpoint_health.sh <<namespace>> gold`
