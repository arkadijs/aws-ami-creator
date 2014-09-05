#!/bin/bash

#export AWS_ACCESS_KEY_ID=
#export AWS_SECRET_ACCESS_KEY=

r=2697
full=bosh-stemcell-$r-aws-xen-ubuntu-trusty-go_agent.tgz
light=light-$full
s3base=https://s3.amazonaws.com/bosh-jenkins-artifacts/bosh-stemcell/aws
dev=/dev/xvdi
name=$(basename $full .tgz)
volume_type=gp2

# http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/UserProvidedKernels.html
declare -A akis=(
    [ap-northeast-1]=aki-176bf516
    [ap-southeast-1]=aki-503e7402
    [ap-southeast-2]=aki-c362fff9
    [eu-west-1]=aki-52a34525
    [sa-east-1]=aki-5553f448
    [us-east-1]=aki-919dcaf8
    [us-west-1]=aki-880531cd
    [us-west-2]=aki-fc8f11cc
  )

set -xe
type jq aws curl
test $(id -u) -eq 0 || exit 1

meta() {
    curl -sS http://169.254.169.254/latest/meta-data/$1
}

wait_volume() {
    local volume=$1
    set +x
    echo -n waiting for volume $volume
    while state=$(aws ec2 describe-volumes --volume-ids $volume | jq -r .Volumes[0].State); test "$state" = "creating"; do
        sleep 5; echo -n '.'; done;
    echo " => $state"
    set -x
}

wait_disk() {
    local dev=$1
    set +x
    echo -n waiting for disk $dev
    until test -e $dev; do sleep 5; echo -n '.'; done;
    echo " => $dev"
    set -x
}

wait_snapshot() {
    local snap=$1
    local region=$2
    set +x
    echo -n waiting for snapshot $snap in $region
    while state=$(aws ec2 describe-snapshots --snapshot-ids $snap --region $region | jq -r .Snapshots[0].State); test "$state" = "pending"; do
        sleep 10; echo -n '.'; done;
    echo " => $state"
    set -x
}

my_zone=$(meta placement/availability-zone)
my_region=${my_zone/%?}
export AWS_DEFAULT_REGION=$my_region
instance=$(meta instance-id)

workdir=$(mktemp -d)
cd $workdir
curl -O $s3base/$light -O $s3base/$full
#ln -s ~/$full

mkdir light
tar xzf $light -C light

volume=$(aws ec2 create-volume --size 2 --volume-type $volume_type --availability-zone $my_zone | jq -r .VolumeId)
wait_volume $volume
aws ec2 attach-volume --volume-id $volume --instance-id $instance --device $dev
wait_disk $dev
tar xzf $full -O image | tar xzf - -O root.img | dd conv=fdatasync bs=1M of=$dev
aws ec2 detach-volume --volume-id $volume
snapshot=$(aws ec2 create-snapshot --volume-id $volume --description $name | jq -r .SnapshotId)
wait_snapshot $snapshot $my_region
aws ec2 delete-volume --volume-id $volume

# us-east-1 already has the AMI
for dest in us-west-1 us-west-2 eu-west-1 ap-southeast-1; do # ap-southeast-2 ap-northeast-1 sa-east-1
    if test $dest = $my_region; then target=$snapshot; else
        target=$(aws ec2 copy-snapshot --source-region $my_region --source-snapshot-id $snapshot --region $dest --description $name |
            jq -r .SnapshotId)
        wait_snapshot $target $dest
    fi
    ami=$(aws ec2 register-image \
        --region $dest \
        --name $name \
        --description $name \
        --architecture x86_64 \
        --kernel-id ${akis[$dest]} \
        --root-device-name /dev/sda1 \
        --virtualization-type paravirtual \
        --block-device-mappings '[
            {"DeviceName":"/dev/sda","Ebs":{"VolumeSize":2,"VolumeType":"'$volume_type'","SnapshotId":"'$target'"}},
            {"DeviceName":"/dev/sdb","VirtualName":"ephemeral0"} ]' |
        jq -r .ImageId)
    echo "    $dest: $ami" >> light/stemcell.MF
done

cd light
rm -f ami.log
tar czf ~/all-regions-$light *
rm -r $workdir
