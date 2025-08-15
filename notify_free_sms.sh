#!/bin/bash
MSG="$1"
URL="https://smsapi.free-mobile.fr/sendmsg?user=${FREE_SMS_USER}&pass=${FREE_SMS_PASS}&msg=$(echo "$MSG" | sed 's/ /%20/g')"
curl -s "$URL" > /dev/null
