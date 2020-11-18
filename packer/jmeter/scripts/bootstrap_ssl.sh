#!/bin/bash
# TODO: Consider Translating to Python with https://github.com/kurtbrose/pyjks
jmeter_path=$(readlink -f /usr/local/lib/jmeter/apache-jmeter-4.0/bin/jmeter)
jmeter_bin=$(dirname $jmeter_path)
keytool -genkey -keyalg RSA -alias rmi -keystore "${jmeter_bin}/rmi_keystore.jks" -storepass changeit -validity 365 -keysize 2048 << EOF
cbs devops
cbs devops
cbs devops
Ann Arbor
MI
US
yes
EOF
