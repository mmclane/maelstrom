#!/bin/bash
mv ${1} /usr/local/lib/jmeter/apache-jmeter-4.0/bin/rmi_keystore.jks
systemctl stop jmeter-daemon
ps aux | grep jmeter-daemon | grep -v grep | awk '{print $2}' | xargs kill -9
systemctl start jmeter-daemon
