#### Rationale

To launch a VM on Amazon Web Services, you must have an AMI registered in the region where the VM will be started. It is quite consuming and error prone to create machine images manually, so this script.

Currently, the script is specific to BOSH stemcell upload, but you could rip out unnecessary parts and use it for any raw Linux image. The script uses [PV Grub] AKI to chainload the kernel.

It must be started on AWS VM (in any region). Configure `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` or use IAM-role provisioned VM.

#### BOSH Stemcell to AMI

It takes time to upload _full_ BOSH stemcell to the director. Much faster is to use _light_ stemcell that is backed by an existing AMI. Standard light [BOSH stemcells] has AMI only in us-west-1 / Virginia. `stemcell-to-ami.sh` script will automate the download of stemcell and AMI creation in all regions. You'll get back `all-regions-light-bosh-stemcell-*.tgz` that has additional regions configured.

[BOSH]: http://docs.cloudfoundry.org/bosh/
[PV Grub]: http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/UserProvidedKernels.html
[BOSH stemcells]: http://bosh-artifacts.cfapps.io/file_collections?type=stemcells
