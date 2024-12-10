#!/bin/bash
set -e

usage() {
    cat <<EOF
This script loads the ssl certificates from openshift and patches the keycloak vanity
route. Updating the credentials without impacting the endusers.

Usages:
    $0 <namespace> <cluster> <year>

Available namespaces:
    - e4ca1d-dev
    - e4ca1d-test
    - e4ca1d-prod
    - eb75ad-dev
    - eb75ad-test
    - eb75ad-prod
Available Clusters
    - gold
    - golddr
Available years
    - YYYY


Examples:
    $ $0 e4ca1d-dev gold 2004
EOF
}

if [ "$#" -lt 3 ]; then
    usage
    exit 1
fi

namespace=$1
cluster=$2
year=$3

pwd="$(dirname "$0")"
source "$pwd/../transition-scripts/helpers/_all.sh"

check_ocp_cluster "$cluster"


KEYCLOAK_ROUTE=$(get_vanity_route_name "$namespace")
KEYCLOAK_URL=$(get_vanity_url "$namespace")
BACKUP_FILE='.env/'"$namespace"'/route-backup-'"$namespace"'-'"$cluster"'-'"$year"'.yaml'

# Get the cluster ip address.
if [ "$cluster" = "golddr" ]; then
    IP="142.34.64.4"
elif [ "$cluster" = "gold" ]; then
    IP="142.34.229.4"
else
    echo "Cluster must be gold or golddr"
    exit 1
fi

check_ssl_cert_expiration() {
    curl -Iv --resolve "$KEYCLOAK_URL":443:"$IP" -H \'Host:"$KEYCLOAK_URL"\' \
    https://"$KEYCLOAK_URL"/auth/realms/master/.well-known/openid-configuration  \
    --stderr - | grep "expire date"
}




# Create a secret in openshift for the current year (will error out if the secret already exists)
oc -n "$namespace" create secret generic loginproxy-ssl-cert-secret."$year" \
 --from-file=private-key=.env/"$namespace"/loginproxy.key \
 --from-file=certificate=.env/"$namespace"/"$KEYCLOAK_URL".txt \
 --from-file=csr=.env/"$namespace"/loginproxy.csr \
 --from-file=TLSChain=.env/"$namespace"/TLSChain.txt \
 --from-file=TLSRoot=.env/"$namespace"/TLSRoot.txt \
 --from-file=TrustedRoot=.env/"$namespace"/TrustedRoot.txt
#  --from-file=ca-chain-certificate=.env/"$namespace"/L1K-for-certs.txt \
#  --from-file=ca-root-certifcate=.env/"$namespace"/L1K-root-for-certs-G2.txt


# Get the current certificate expiration date
check_ssl_cert_expiration

# Retrieve and decode the secrets from openshift cluster.

keyEncoded=$(kubectl -n "$namespace" get secret loginproxy-ssl-cert-secret."$year" -o jsonpath='{.data.private-key}' )
key=$(echo -e "$keyEncoded" | base64 --decode | sed ':a;N;$!ba;s/\n/\\n/g')

certificateEncoded=$(kubectl -n "$namespace" get secret loginproxy-ssl-cert-secret."$year" -o jsonpath='{.data.certificate}')
certificate=$(echo -e "$certificateEncoded" | base64 --decode | sed ':a;N;$!ba;s/\n/\\n/g')

caCertificateEncoded=$(kubectl -n "$namespace" get secret loginproxy-ssl-cert-secret."$year" -o jsonpath='{.data.TLSChain}')
caCertificate=$(echo -e "$caCertificateEncoded" | base64 --decode | sed ':a;N;$!ba;s/\n/\\n/g')

# Creatre a backup of the old route in case something goes wrong, append to file on multiple runs
kubectl -n "$namespace" get route "$KEYCLOAK_ROUTE" -o yaml >> "$BACKUP_FILE"

kubectl -n "$namespace" patch route "$KEYCLOAK_ROUTE" -p '{"spec":{"tls":{"certificate":"'"$certificate"'", "key":"'"$key"'", "caCertificate":"'"$caCertificate"'" }}}'


# Get the new certificate expiration date
check_ssl_cert_expiration
