JMETER_PORT=1099
JMETER_IP=$(ip addr show eth0 | grep inet | grep -v inet6 | awk '{print $2}' | cut -d'/' -f1)
/usr/bin/jmeter -Djava.rmi.server.hostname=${JMETER_IP} \
          -Dserver_port=${JMETER_PORT} \
          -n -s -j /tmp/jmeter-server.log
