#!/bin/bash
# Currently only supports IPv4
# You only need to fill in the fields below
CF_RECORD_NAME="sub.example.com" // you can use $(hostname -f) to get the machine name + dhcp domain
CF_USER="user@example.com"
CF_KEY="th1s_1s_n0t_a_r3al_k3y"


# Currently it uses an ip from one of the RFC1918 ranges. If you want to use your external ip, uncomment the second line
IP="internal"
#IP="external"

# Only use this is if IP = internal
ETH_ADAPTER="ens33"

# This only works when IP = external or when the machine has an non-RFC1918 range on its ETH_ADAPTER
ENABLE_PROXY=false

# Stop changing stuff here
#===========================================================================================

# Only works for domains with a single TLD (.com, .nl, .de) not for domains like .co.uk
CF_ZONE_NAME=$(awk -F\. '{print $(NF-1) FS $NF}' <<< $CF_RECORD_NAME)
CF_ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$CF_ZONE_NAME" -H "X-Auth-Email: $CF_USER" -H "X-Auth-Key: $CF_KEY" -H "Content-Type: application/json" | grep -Po '(?<="id":")[^"]*' | head -1 )
CF_RECORD=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?name=$CF_RECORD_NAME" -H "X-Auth-Email: $CF_USER" -H "X-Auth-Key: $CF_KEY" -H "Content-Type: application/json")
CF_RECORD_ID=$(grep -Po '(?<="id":")[^"]*' <<< $CF_RECORD | head -1)
CF_RECORD_IP=$(grep -Po '(?<="content":")[^"]*' <<< $CF_RECORD | head -1)

if [ $IP == "internal" ]
then
  ENABLE_PROXY=false
  IPADDR=$(ip -4 addr show $ETH_ADAPTER | grep inet | awk '{print $2}' | awk -F "/" '{print $1}')
else
  IPADDR=$(curl -s ifconfig.co)
fi

# This checks if the record exists already, if it does not it will create the record
if [ "$(grep -Po '(?<="id":")[^"]*' <<< $CF_RECORD | head -1)" == "" ]
then
  echo "There is no record for that subdomain yet, we will now create one:"
  printf "Type: A \nName: $CF_RECORD_NAME\nValue: $IPADDR\n"

  curl -s -o /dev/null -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
       -H "X-Auth-Email: $CF_USER" \
       -H "X-Auth-Key: $CF_KEY" \
       -H "Content-Type: application/json" \
       --data '{"type":"A","name":"'$CF_RECORD_NAME'","content":"'${IPADDR}'","ttl":1,"proxied":'${ENABLE_PROXY}'}'

# Else the record is already there, we will then check if the record IP matches our machine ip. If it does not, we will update the record ip.
elif [ $CF_RECORD_IP != $IPADDR ]
then
  echo "The server IP ($IPADDR) is not the same as the record IP ($CF_RECORD_IP), record will be updated."

  curl -s -o /dev/null -X PUT "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$CF_RECORD_ID" \
       -H "X-Auth-Email: $CF_USER" \
       -H "X-Auth-Key: $CF_KEY" \
       -H "Content-Type: application/json" \
       --data '{"type":"A","name":"'$CF_RECORD_NAME'","content":"'${IPADDR}'","ttl":1,"proxied":'${ENABLE_PROXY}'}'
elif [ $CF_RECORD_IP == $IPADDR ]
then
  echo "The server IP ($IPADDR) is equal to the record IP ($CF_RECORD_IP), record will not be updated."
else
  echo "Unknown error occured, please verify the record name, user and key you supplied."
fi
exit
