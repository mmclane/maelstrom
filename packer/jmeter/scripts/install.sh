#!/bin/bash
set -ex

install_jmeter_plugin() {
  # Installs plugins for jmeter specified as <name>-<version>
  # Usage: install_jmeter_plugin PLUGIN
  plugin=$1
  if [[ -z "${plugin}" ]]; then
    return 1
  fi
  curl -O "https://jmeter-plugins.org/files/packages/${plugin}.zip"
  sudo unzip -o -d "/usr/local/lib/jmeter/apache-jmeter-${JMETER_VERSION}" "${plugin}.zip"
  rm "${plugin}.zip"
}

# Uncomment this to add the lots public key as an authorized key
# Useful for debugging failed packers
# echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC4TDzPFAASjSNjQsTORR1BrfK9Uv36wCKcOZUz3smgBNr2gdfV/+94qTLSbrcsXYT71tlrgOLyo6NxwbUZRwC2qXIYto0KqeXnF0+rxxN7bp7WCbY0Sit7DJnsobfD5d9km2euukfkE0m2J8FJz2nZrELR0vee4GY4ja4zAmKXD70GTauQo1PRbqZ+YzJ33V3YQfEvq0jB+gVMTffCHEwTGrDW/sY6HZee8kgdA4FHibQNrZM7/9f+DAK+Usdl7fwY6bt8qCDJ7dcYmx/O9CEBphyu5xf2l7RrFjgrQfKflFNh4SrhJvtafesq8bz6xaIJRMNqFd69s5qNpN6gzFrP1Onib1gtvC9GKRCx4ACpzW4YGWnPZDHn4vDqv4QSUiCxwNW7B1yub645V0tnpNBbUik6MoO+IJYrTXihTyjQJ4gEd482s4kYFOsexOnR6O5KF7FSNVaZ5in+Ke7iGYDK5kZOSc17+te3bOKzcFLYYgWn3MgiRtWhKvVMr+EK7ZPAEgIyKpvl+NiyX+ZBd3hkR357EG1KXN2FkMWxxa84pPgOlxj2Thsw32vIYLnSqUQlc5p26qDxzEZvjKLXNZshf3Dxa42WV8dGM2KHgtRhMFFCbBEyQXkX6A8yobxR8DsYsGnWS/HlXqtPSNLEppCRjfkMzzANVDgOF0t4uKl3SQ== m.mclane@marvin" | sudo -H -u packer tee -a /home/packer/.ssh/authorized_keys

sudo yum update -y

sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo sh -c 'echo -e "[azure-cli]\nname=Azure CLI\nbaseurl=https://packages.microsoft.com/yumrepos/azure-cli\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/azure-cli.repo'
sudo yum -y install https://centos7.iuscommunity.org/ius-release.rpm

sudo yum update -y
sudo yum install -y \
  curl \
  unzip \
  azure-cli \
  jq \
  openssh-server \
  python-virtualenv \
  python36u \
  python3-devel

# Install OpenJDK
curl -O "https://download.java.net/java/GA/jdk9/9.0.4/binaries/openjdk-${JDK_VERSION}_linux-x64_bin.tar.gz"
tar xzf "openjdk-${JDK_VERSION}_linux-x64_bin.tar.gz"
sudo mkdir -p /usr/local/lib/openjdk
sudo mv "jdk-${JDK_VERSION}" "/usr/local/lib/openjdk"
sudo update-alternatives --install "/usr/bin/java" "java" "/usr/local/lib/openjdk/jdk-${JDK_VERSION}/bin/java" 1
sudo update-alternatives --install "/usr/bin/javac" "javac" "/usr/local/lib/openjdk/jdk-${JDK_VERSION}/bin/javac" 1
sudo update-alternatives --install "/usr/bin/keytool" "keytool" "/usr/local/lib/openjdk/jdk-${JDK_VERSION}/bin/keytool" 1
rm "openjdk-${JDK_VERSION}_linux-x64_bin.tar.gz"

# Install jmeter
curl -O "https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz"
tar xzf "apache-jmeter-${JMETER_VERSION}.tgz"
sudo mkdir -p /usr/local/lib/jmeter
sudo mv "apache-jmeter-${JMETER_VERSION}" /usr/local/lib/jmeter
sudo update-alternatives --install "/usr/bin/jmeter" "jmeter" "/usr/local/lib/jmeter/apache-jmeter-${JMETER_VERSION}/bin/jmeter" 1
rm "apache-jmeter-${JMETER_VERSION}.tgz"

# Install jmeter plugins
install_jmeter_plugin "jpgc-tst-2.2"
install_jmeter_plugin "jpgc-functions-2.0"
install_jmeter_plugin "jpgc-dummy-0.2"
install_jmeter_plugin "jpgc-fifo-0.2"
install_jmeter_plugin "jpgc-graphs-basic-2.0"
install_jmeter_plugin "jpgc-perfmon-2.1"
install_jmeter_plugin "jpgc-casutg-2.5"
install_jmeter_plugin "jpgc-ffw-2.0"

sudo sed -i "s|#server.rmi.ssl.keystore.file=rmi_keystore.jks|server.rmi.ssl.keystore.file=/usr/local/lib/jmeter/apache-jmeter-${JMETER_VERSION}/bin/rmi_keystore.jks|g" "/usr/local/lib/jmeter/apache-jmeter-${JMETER_VERSION}/bin/jmeter.properties"
chmod +x /tmp/bootstrap_ssl.sh

## Place file to be used prior to starting jmeter-server
# Had to be placed in tmp due to permissions issues in packer
sudo mv /tmp/jmeter-daemon.service /etc/systemd/system/jmeter-daemon.service
sudo mv /tmp/bootstrap_ssl.sh /usr/local/bin/
sudo mv /tmp/update_keystore.sh /usr/local/sbin/
sudo chmod 700 /usr/local/sbin/update_keystore.sh

# Give jmeter ability to update rmi_keystore
sudo echo "jmeter  ALL=(root) NOPASSWD: /usr/local/sbin/update_keystore.sh" > /tmp/10-jmeter
sudo mv /tmp/10-jmeter /etc/sudoers.d/10-jmeter
sudo chown 0:0 /etc/sudoers.d/10-jmeter
sudo chmod 440 /etc/sudoers.d/10-jmeter

# Create jmeter user for running tests
sudo useradd -m -s /bin/bash jmeter
sudo -H -u jmeter mkdir -p /home/jmeter/.ssh/
sudo -H -u jmeter ssh-keygen -t rsa -b 2048 -C "jmeter-user" -f /home/jmeter/.ssh/id_rsa -N ""
sudo -H -u jmeter cp /home/jmeter/.ssh/id_rsa.pub /home/jmeter/.ssh/authorized_keys
sudo -H -u jmeter chmod 700 /home/jmeter/.ssh
sudo -H -u jmeter chmod 600 /home/jmeter/.ssh/authorized_keys
sudo mv /tmp/start_jmeter.sh /home/jmeter
sudo chmod u+x /home/jmeter/start_jmeter.sh

# Create virtualenv for the scripts
sudo -H -u jmeter /usr/bin/virtualenv -p $(which python3.6) /home/jmeter/venv
sudo -H -u jmeter /home/jmeter/venv/bin/pip install --upgrade pip
sudo -H -u jmeter /home/jmeter/venv/bin/pip install azure-storage-blob azure-storage-queue paramiko
sudo -H -u jmeter /home/jmeter/venv/bin/pip install pandas --no-build-isolation
