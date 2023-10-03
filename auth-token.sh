#!/bin/bash

if [ -z "$CLIENT_ID" ]; then
    echo "CLIENT_ID not set"
    exit 1
fi

if [ -z "$CLIENT_SECRET" ]; then
    echo "CLIENT_SECRET not set"
    exit 1
fi

if [ -z "$SCOPE" ]; then
    SCOPE="read_station read_thermostat read_camera access_camera read_presence access_presence read_smokedetector read_homecoach"
    echo "SCOPE not set, using default: '$SCOPE'"
    echo ""
fi



STATE="randomstring$RANDOM"
# we assume port 54321 will always fail
REDIRECT_URI="https://127.0.0.1:54321/here"

rawurlencode() {
  local string="${1}"
  local strlen=${#string}
  local encoded=""
  local pos c o

  for (( pos=0 ; pos<strlen ; pos++ )); do
     c=${string:$pos:1}
     case "$c" in
        [-_.~a-zA-Z0-9] ) o="${c}" ;;
        * )               printf -v o '%%%02x' "'$c"
     esac
     encoded+="${o}"
  done
  echo "${encoded}"    # You can either set a return variable (FASTER)
  REPLY="${encoded}"   #+or echo the result (EASIER)... or both... :p
}

echo "Goto: https://api.netatmo.com/oauth2/authorize?client_id=$CLIENT_ID&redirect_uri=$(rawurlencode "$REDIRECT_URI")&scope=$(rawurlencode "$SCOPE")&state=$STATE"
echo ""
echo "After login there will be an error, which is ok. Copy the 'code' from the URL bar and paste it here."

# fullname="USER INPUT"
read -p "Enter code (part after 'code='): " CODE
echo "got: >$CODE<"
echo ""

http -f -b POST https://api.netatmo.com/oauth2/token \
    Host:api.netatmo.com \
    Content-Type:application/x-www-form-urlencoded\;charset=UTF-8 \
    grant_type=authorization_code \
    client_id=$CLIENT_ID \
    client_secret=$CLIENT_SECRET \
    "scope=$SCOPE" \
    "code=$CODE" \
    redirect_uri=$REDIRECT_URI


# http POST "https://api.netatmo.com/oauth2/authorize?client_id=$CLIENT_ID&redirect_uri=$REDIRECT_URI&scope=$SCOPE&state=$STATE"
