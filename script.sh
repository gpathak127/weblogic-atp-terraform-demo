# cp cmd.json cmd.json.copy
# cp wls.sh wls.sh.copy
# cp terraform/vars.tf terraform/vars.tf.copy
export compartmentId="ocid1.compartment.oc1..aaaaaaaamn7edtntfc7itudleec7qj23hhnx6pzufscvozzhnxqurj4gboba"
export region="eu-amsterdam-1"
export ad="Vihs:eu-amsterdam-1-AD-1"
sed -i "s|COMPARTMENT_ID|${compartmentId}|g" terraform/vars.tf
sed -i "s|REGION|${region}|g" terraform/vars.tf
sed -i "s|AD|${ad}|g" terraform/vars.tf
#export OCID="ocid1.instance.oc1.eu-amsterdam-1.anqw2ljruevftmqct6gofznymqk7sj6chg5xefspfamgofx3il3wp5bwuv7a"
if [ -z "$OCID" ]; then
    echo "Creating Terraform .."
    cd terraform
    terraform init > tf.out
    terraform apply -auto-approve -no-color > ../tf.out &
    cd ..
    export tries=0
    export OCID=""
    while [ $tries -le 100 ] && [[ $OCID == "" ]] 
    do
        tail -n 1 tf.out > out.txt
        cat out.txt
        export OCID=$(grep -oP '(?<=ocid = ")[^"]*' out.txt)
        tries=$(( $tries + 1 ))
        sleep 10
    done
fi
echo "Terraform done."
cd app
mvn package -q
cd ..
export preauth=$(oci os preauth-request create -bn wls-artifacts --access-type AnyObjectRead --name artifacts-bucket-preauth --time-expires 2024-01-01 | jq '.data."access-uri"' | tr -d '"')
sed -i "s|REGION|$region|g" wls.sh
sed -i "s|SOURCE_URI|$preauth|g" wls.sh
sed -i "s|REGION|$region|g" cmd.json
sed -i "s|COMPARTMENT_ID|${compartmentId}|g" cmd.json
sed -i "s|INSTANCE_OCID|$OCID|g" cmd.json
sed -i "s|SOURCE_URI|$preauth|g" cmd.json
oci os object put --force -bn wls-artifacts --file app/target/app.war
oci os object put --force -bn wls-artifacts --file wls.sh
echo "Waiting 3 mins WLS to start up .. get a coffee ;)"
spin='-\|/'
export tries=0
i=0
while [ $tries -le 180 ]
do
  i=$(( (i+1) %4 ))
  printf "\r${spin:$i:1}"
  sleep 1
  tries=$(( $tries + 1 ))
done
echo "Starting app deployment using VM instance agent ..."
export cmd=$(oci instance-agent command create --from-json file://cmd.json | jq '.data.id' | tr -d '"')
export tries=0
export status=''
while [ $tries -le 1000 ] && [[ $status != 'SUCCEEDED' ]] 
do
  export status=$(oci instance-agent command-execution get --instance-id $OCID --command-id $cmd | jq '.data."lifecycle-state"' | tr -d '"')
  i=$(( (i+1) %4 ))
  printf "\r${spin:$i:1}"
  tries=$(( $tries + 1 ))
done
export par=$(oci os preauth-request list -bn wls-artifacts | jq '.data[].id' | tr -d '"')
oci os preauth-request delete -bn wls-artifacts --par-id $par --force
oci os object bulk-delete -bn wls-artifacts --force
oci os object bulk-delete -bn wls-create-domain --force
cp cmd.json.copy cmd.json
cp wls.sh.copy wls.sh
rm -f out.txt
rm -f tf.out
# cp terraform/vars.tf.copy terraform/vars.tf