#!/bin/bash
#set -ex
################################################################################
# User Defined Variables
nameVpc=""
nameDomain=""
nameCluster=""
clusterDomain=""

# Enabled Regions
# Hard Coded for now
awsRegion1="us-gov-west-1"
awsRegion2="us-gov-west-1"
awsRegion3="us-gov-west-1"

# Working Variables
dirBase="/root/PlatformOne"

################################################################################
# Base Logging 
run_log () {
  if   [[ $1 == 0 ]]; then
    echo "   $2" 
  elif [[ $1 == 1 ]]; then
    echo "   $2"
    exit 1
  fi
}

################################################################################
# Write Install Config .yaml
write_machine_api_secrets_yaml () {
run_log 0 "Writing machine api credential yaml files"

cat <<EOF > ${dirArtifacts}/bak/openshift/99_openshift-ingress-operator_cloud-credentials-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloud-credentials
  namespace: openshift-ingress-operator
data:
  aws_access_key_id: `awk '/aws_access_key_id/ {print $3}' ${dirArtifacts}/.aws/govcloud.credentials | base64`
  aws_secret_access_key: `awk '/aws_secret_access_key/ {print $3}' ${dirArtifacts}/.aws/govcloud.credentials | base64`
EOF

cat <<EOF > ${dirArtifacts}/bak/openshift/99_openshift-machine-api_aws-cloud-credentials-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: aws-cloud-credentials
  namespace: openshift-machine-api
data:
  aws_access_key_id: `awk '/aws_access_key_id/ {print $3}' ${dirArtifacts}/.aws/govcloud.credentials | base64`
  aws_secret_access_key: `awk '/aws_secret_access_key/ {print $3}' ${dirArtifacts}/.aws/govcloud.credentials | base64`
EOF

cat <<EOF > ${dirArtifacts}/bak/openshift/99_openshift-image-registry_installer-cloud-credentials-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: installer-cloud-credentials
  namespace: openshift-image-registry
data:
  aws_access_key_id: `awk '/aws_access_key_id/ {print $3}' ${dirArtifacts}/.aws/govcloud.credentials | base64`
  aws_secret_access_key: `awk '/aws_secret_access_key/ {print $3}' ${dirArtifacts}/.aws/govcloud.credentials | base64`
EOF

}

################################################################################
# Write Install Config .yaml
write_install_config_yaml () {
run_log 0 "Staging install-config.yaml"

cat <<EOF > ${dirArtifacts}/bak/install-config.yaml
apiVersion: v1
additionalTrustBundle: |
`awk '{printf "  %s\n", $0}' < ${dirArtifacts}/ssl/${clusterDomain}.crt`
baseDomain: ${nameDomain}
imageContentSources:
- mirrors:
  - registry.${clusterDomain}/ocp-${versOCP}
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - registry.${clusterDomain}/ocp-${versOCP}
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
compute:
- name: worker
  replicas: 2
  platform:
    aws:
      type: t2.xlarge
      zones:
      - us-east-1a
controlPlane:
  name: master
  replicas: 3
  platform:
    aws:
      type: t2.xlarge
      zones:
      - us-east-1a
metadata:
  name: ${nameCluster}
platform:
  aws:
    amiID: ami-e9426288 
    region: us-east-1
pullSecret: '`cat /root/.docker/config.json`'
sshKey: "`cat /root/.ssh/id_rsa_${clusterDomain}.pub`"
publish: Internal
EOF

# Stage to data directory
cp ${dirArtifacts}/bak/install-config.yaml ${dirArtifacts}/data/install-config.yaml
}

################################################################################
# Write Self Signed Certificate & Key
run_log 0 "Staging optional registry node self signed certificates"
write_self_signed_cert () {
openssl req \
  -x509 \
  -nodes \
  -sha256 \
  -days   3650 \
  -newkey rsa:4096 \
  -subj   "/CN=${clusterDomain}" \
  -out    ${dirArtifacts}/ssl/${clusterDomain}.crt  \
  -keyout ${dirArtifacts}/ssl/${clusterDomain}.key  \
  -addext "subjectAltName=DNS:registry.${clusterDomain},DNS:${nameDomain},IP:10.0.1.10" 2>&1 1>/dev/null
}

################################################################################
# Stage docker config quay pull secret
write_docker_config_json () {
export emailAdmin="admin@${nameDomain}"

cat <<EOF > ${dirArtifacts}/bak/.docker/config.json
${quaySecret}
EOF

# Append private registry credentials
jq -e ".auths += {\"registry.${clusterDomain}\": {\"auth\": \"$(echo -n ${nameVpc}:${nameVpc} | base64 -w0)\", \"email\": "env.emailAdmin"}}" ${dirArtifacts}/bak/.docker/config.json \
    | jq -c > ${dirArtifacts}/.docker/config.json

cp -f ${dirArtifacts}/bak/.docker/config.json /root/.docker/config.json
}

################################################################################
# Gather Red Hat Quay Image Repository Pull Secret
prompt_usr_quay_secret () {
  run_log 0 "On the Cluster Manager UPI portal, find and click: 'Copy Pull Secret'"

  # Prompt user to paste secret
  quaySecret=$(read -srp "    >> Please paste your pull secret and hit 'Enter'.. (Secret is masked): " quaySecret; echo ${quaySecret})
}

################################################################################
# Request Red Hat User Access
get_rh_pull_secret () {
echo
while true; do
  read -rp "    >> Do you have a login for access.redhat.com? (yes/no): " yn
    case $yn in
      [Yy]* ) run_log 0 "Go ahead and open the RH Cluster Manager Portal:" ; 
              run_log 0 "      https://cloud.redhat.com/openshift/install/metal/user-provisioned" ; 
              prompt_usr_quay_secret
              break
              ;;
      [Nn]* ) run_log 0 "Please register for a commercial or developer account and try again:" ;
              run_log 0 "      https://access.redhat.com" ; 
              run_log 0 "      https://developers.redhat.com" ;
              ;;
          * ) echo "$SEP_2 Please answer yes or no." ;;
    esac
  break
done
echo
}

################################################################################
# Prompt user for aws keys
write_user_data_b64 () {
clear && echo
run_log 0 "Generating RHCOS Bastion node base64 encoded user-data"

cat <<EOF | base64 -w0 > ${dirArtifacts}/user-data/bastion-json.b64; echo
{"ignition":{"config":{},"security":{"tls":{}},"timeouts":{},"version":"2.2.0"},"networkd":{},"passwd":{"users":[{"name":"core","sshAuthorizedKeys":["$(cat ${dirArtifacts}/.ssh/id_rsa_${clusterDomain}.pub)"]}]},"storage":{},"systemd":{}}
EOF

run_log 0 "Generating RHCOS Bootstrap node base64 encoded user-data"
cat <<EOF | base64 -w0 > ${dirArtifacts}/user-data/bootstrap-json.b64; echo
{"ignition":{"config":{"append":[{"source":"http://registry.${clusterDomain}/bootstrap.ign","verification":{}}]},"security":{},"timeouts":{},"version":"2.2.0"},"networkd":{},"passwd":{},"storage":{},"systemd":{}}
EOF

run_log 0 "Generating RHCOS Master node(s) base64 encoded user-data"
cat <<EOF | base64 -w0 > ${dirArtifacts}/user-data/master-json.b64; echo
{"ignition":{"config":{"append":[{"source":"http://registry.${clusterDomain}/master.ign","verification":{}}]},"security":{},"timeouts":{},"version":"2.2.0"},"networkd":{},"passwd":{},"storage":{},"systemd":{}}
EOF
}

################################################################################
# Prompt user for aws keys
usr_prompt_aws_keys () {
  run_log 0 "Click on 'Create access key'"

  # Prompt user to paste secret
  read  -rp "    >> Please copy/paste the 'Access Key ID': " access_KEYID;
  read -srp "    >> Please copy/paste the 'Secret Access Key' (Secret is masked): " access_KEYSECRET;

cat <<EOF > ${dirArtifacts}/.aws/${1}.credentials
; https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html
[default]
aws_access_key_id = ${access_KEYID}
aws_secret_access_key = ${access_KEYSECRET}
EOF

[[ $1 == "commercial" ]] && cp -f ${dirArtifacts}/.aws/${1}.credentials ${HOME}/.aws/credentials
access_KEYSECRET=''
access_KEYID=''
}

################################################################################
# Collect AWS Commercial Credentials
get_aws_commercial_credentials () {
clear && echo
run_log 0 "Open the Commercial AWS IAM Security Credentials Portal:" ; 
run_log 0 "      https://console.aws.amazon.com/iam/home#/security_credentials" ; 

usr_prompt_aws_keys commercial
}

################################################################################
# Collect AWS Gov Cloud Credentials
get_aws_govcloud_credentials () {
clear && echo
run_log 0 "Open the Gov Cloud AWS IAM Security Credentials Portal:" ; 
run_log 0 "      https://console.amazonaws-us-gov.com/iam/home#/security_credentials" ; 

usr_prompt_aws_keys govcloud
}

################################################################################
# Generate cloud deploy ssh keys
run_ssh_keygen () {
clear && echo
  run_log 2 "Creating new ssh keys for cluster deploy..."

  # Generate ssh keys
  ssh-keygen -b 4086 -t rsa -C "core@${clusterDomain}" \
             -f ${dirArtifacts}/.ssh/id_rsa_${clusterDomain}

  cp -f ${dirArtifacts}/.ssh/id_rsa_${clusterDomain}* /root/.ssh/
}

################################################################################
# One Time Artifact Environment Staging
append_bashrc () {

source ${dirBase}/*/environment

cat <<EOF >> "${HOME}/.bashrc"
# Source artifact envs only for interactive sessions
case \$- in *i*)
        source ${dirArtifacts}/environment
esac
EOF
}

################################################################################
# One Time Artifact Environment Staging
run_init_stage () {
# Create directory structure
mkdir -p ${dirArtifacts}/{log,auth,ssl,data,registry,user-data,bak/openshift/,bak/.docker,.docker,.ssh,.aws}

export dirBase="${dirBase}"
export nameVpc="${nameVpc}"
export nameDomain="${nameDomain}"
export nameCluster="${nameCluster}"
export clusterDomain="${clusterDomain}"
export dirArtifacts="${dirArtifacts}"
export awsRegion1="${awsRegion1}"
export awsRegion2="${awsRegion2}"
export awsRegion3="${awsRegion3}"

# Stage environment variables
cat <<EOF > ${dirArtifacts}/environment
export versOCP="${versOCP}"
export dirBase="${dirBase}"
export nameVpc="${nameVpc}"
export nameDomain="${nameDomain}"
export nameCluster="${nameCluster}"
export clusterDomain="${clusterDomain}"
export dirArtifacts="${dirArtifacts}"
export awsRegion1="${awsRegion1}"
export awsRegion2="${awsRegion2}"
export awsRegion3="${awsRegion3}"
EOF

[[ $(grep PlatformOne ${HOME}/.bashrc ; echo $?) == 0 ]] \
   || append_bashrc "${HOME}/.bashrc"

}

################################################################################
# One Time Artifact Environment Staging
run_init_usr_prompt () {

  # Verify Information
  prompt_verify () {
    echo " 
    Artifact Environment Variables:
      VPC Name:       ${nameVpc}
      Cluster Name:   ${nameCluster}
      Base Domain:    ${nameDomain}
      Cluster Domain: ${clusterDomain}
    "

  while true; do
    read -p "    Please confirm these details are correct (Yes/No): " verify
    case ${verify} in
      [Yy]* ) run_log 0 "User Confirmed. Continuing ..." ; 
	      break
	      ;;
      [Nn]* ) run_log 1 "User Rejected.  Terminating ..." ;;
          * ) run_log 3 "Please answer Yes or No"         ;;
    esac
  done
  }

  # Prompt user for AWS VPC Name
  prompt_nameVpc () {
    read -p '    Please enter your AWS VPC name: ' nameVpc
  }

  # Prompt user for AWS VPC Name
  prompt_nameCluster () {
  echo "    
    Please enter a cluster name which will be prepended to the Base Domain
    This is a unique and arbitrary name which will be appended as a subdomain.
      Example entry:             
        cluster
      Which would prepend to become:
        cluster.cloud.com 
        cluster.anchovy.dev"
  read -p '    Cluster Name: ' nameCluster
  clusterDomain="${nameCluster}.${nameDomain}"
  dirArtifacts="${dirBase}/${clusterDomain}"
  }

  # Prompt user for Base Domain Name
  prompt_nameDomain () {
  echo "    
    Please enter a base domain name for this environment
    This may be an arbitrary local only domain, or a domain you own the rights to.
      Example:             
        cloud.com
        anchovy.dev"
  read -p '    Base Domain : ' nameDomain ;
  }

  # Call subroutines
  sub_run () {
    clear && echo
    prompt_nameDomain
    prompt_nameCluster
    prompt_nameVpc
    echo && prompt_verify
  }

sub_run
}

################################################################################
# User Introduction
run_info () {
run_log 0 '
    This will walk you through preparing your AWS Gov OCP asset management
    environment required to generate your RHCOS Ignition configuration data.
    
    This walk through requires all of the following:
      1. AWS Commercial Credentials:
           @ https://console.aws.amazon.com/iam/home#/security_credentials

      2. AWS Gov Cloud Credentials:
           @ https://console.amazonaws-us-gov.com/iam/home#/security_credentials

      3. A Red Hat Developer or Subscription account:
           Developer Sign up          @ https://developers.redhat.com/register/ 
           Commercial Register/Login  @ https://access.redhat.com

      4. The UPI OpenShift Cluster Manager Portal:
            @ https://cloud.redhat.com/openshift/install/metal/user-provisioned
'
}

# Function call order
run () {
  run_log 0 ' Welcome to the ContainerOne OpenShift Artifact Prep Utility'
  run_info
  run_init_usr_prompt
  run_init_stage 
  append_bashrc
  run_ssh_keygen
  get_aws_commercial_credentials
  get_aws_govcloud_credentials
  write_user_data_b64 
  get_rh_pull_secret
  write_docker_config_json 
  write_self_signed_cert
  write_install_config_yaml
  write_machine_api_secrets_yaml 
}

run
