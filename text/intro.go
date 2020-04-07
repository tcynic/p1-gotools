package text

import "fmt"

// PrintIntro prints an introductory text blob
func PrintIntro() {
	fmt.Println(
		`This will walk you through preparing your AWS Gov OCP asset management
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
               `)
}
