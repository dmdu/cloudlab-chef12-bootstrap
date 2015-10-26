#!/bin/bash

# This script installs Chef server and workstation locally
# Author: Dmitry Duplyakin
# Date: 06/10/15
set +x

# Configure email
BOOTDIR=/var/emulab/boot
SWAPPER=`cat $BOOTDIR/swapper`
OURDOMAIN=`cat $BOOTDIR/mydomain`
if [ "$SWAPPER" = "geniuser" ]; then
    SWAPPER_EMAIL=`geni-get slice_email`
else
    SWAPPER_EMAIL="$SWAPPER@$OURDOMAIN"
fi
export DEBIAN_FRONTEND=noninteractive
APTGETINSTALLOPTS='-y'
APTGETINSTALL="apt-get install $APTGETINSTALLOPTS"
$APTGETINSTALL dma

CHEF_ADMIN=admin
CHEF_ADMIN_PASS=`openssl rand -base64 10`
ADMIN_EMAIL=$SWAPPER_EMAIL
USER_KEY=admin.pem
ORG=admingroup
ORG_KEY=admingroup.pem
REPO_DIR=/chef-repo
GIT_REPO=https://github.com/emulab/chef-repo.git
CREDS=/root/.chefauth
DOTCHEF=/root/.chef

echo $CHEF_ADMIN > $CREDS
echo $CHEF_ADMIN_PASS >> $CREDS

printf "\n\n\n"
echo `date` "--- Starting to install Chef "
set -x

# Make sure only root can run the script
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 
   exit 1
fi

HOST=`hostname -f`

# Required packages
apt-get update
apt-get install -y wget expect curl git

# Install Chef server
cd /tmp
#wget https://web-dl.packagecloud.io/chef/stable/packages/ubuntu/trusty/chef-server-core_12.1.2-1_amd64.deb --directory-prefix=/tmp
wget https://web-dl.packagecloud.io/chef/stable/packages/ubuntu/trusty/chef-server-core_12.2.0-1_amd64.deb
dpkg -i chef-server-core*
chef-server-ctl reconfigure

# Install Chef management console 
curl -s https://packagecloud.io/install/repositories/chef/stable/script.deb.sh | sudo bash
apt-get install -y opscode-manage
chef-server-ctl reconfigure
opscode-manage-ctl reconfigure

# Install Push Server
chef-server-ctl install opscode-push-jobs-server
chef-server-ctl reconfigure
opscode-push-jobs-server-ctl reconfigure

# Enable reporting
chef-server-ctl install opscode-reporting
chef-server-ctl reconfigure
opscode-reporting-ctl reconfigure

# Setting credentials
mkdir $DOTCHEF
set +x
chef-server-ctl user-create $CHEF_ADMIN Owner Owner $ADMIN_EMAIL $CHEF_ADMIN_PASS --filename "$DOTCHEF/$USER_KEY"
chef-server-ctl org-create $ORG "Owner Group" --association_user $CHEF_ADMIN --filename "$DOTCHEF/$ORG_KEY"
set -x


# Install Chef workstation
cd /tmp
#wget https://opscode-omnibus-packages.s3.amazonaws.com/ubuntu/12.04/x86_64/chefdk_0.4.0-1_amd64.deb
wget https://opscode-omnibus-packages.s3.amazonaws.com/ubuntu/12.04/x86_64/chefdk_0.7.0-1_amd64.deb
dpkg -i chefdk*
chef verify

#Install knife extension for push jobs
chef gem install knife-push 

cat > $DOTCHEF/knife.rb << END
current_dir = File.dirname(__FILE__)
log_level                :info
log_location             STDOUT
node_name                "$CHEF_ADMIN"
client_key               "#{current_dir}/$USER_KEY"
validation_client_name   "$ORG-validator"
validation_key           "#{current_dir}/$ORG_KEY"
chef_server_url          "https://`hostname -f`/organizations/$ORG"
syntax_check_cache_path  "$DOTCHEF/syntaxcache"
cookbook_path            ["$REPO_DIR/cookbooks"]
END

# Make knife trust the server's certificate
knife ssl fetch

# Copy the repo
git clone $GIT_REPO $REPO_DIR

# Get the push-jobs cookbook and its dependecies
knife cookbook site install push-jobs

# Get the dependecies for cookbooks in $GIT_REPO. This list will grow as more cookbooks are added in the repo
knife cookbook site install nfs

# Warning: configuration below works but is very sensitive
# If hostbased authentication is configured, the host key might not be used with Chef's Ruby implementation of SSH
# Workaround: add the host private key in ssh agent
# By adding the following lines to root's .bashrc, we ensure that the new key is used with Chef's knife connections
# Following directions from: http://blog.joncairns.com/2013/12/understanding-ssh-agent-and-ssh-add/
profile="/root/.bashrc"
hostkey="/etc/ssh/ssh_host_rsa_key"
echo "Updating $profile to enable the new key"
echo "# Enabling usage of host key with Chef's knife connections" >> $profile
echo 'source /root/ssh-find-agent.sh' >> $profile
echo 'set_ssh_agent_socket' >> $profile
echo "ssh-add $hostkey &> /dev/null" >> $profile

eval `ssh-agent -s`
ssh-add $hostkey

# Allow ssh connects to itself
cat "$hostkey.pub" >> /root/.ssh/authorized_keys

#echo "Installing xmlstarlet package for parsing manifest"
dpkg -l | grep xmlstarlet
if [ $? -ne 0 ]; then
  apt-get update
  apt-get -y install xmlstarlet
fi

# Bootsrap all client nodes
# Warning: obviously sensitive parsing
# Get short node names from the manifest (the portion before . in the full names)
#names=`geni-get manifest | sed -r 's/<node/\n<node/g' | grep -E ".*<node.*/node>.*" | sed -r "s/.*host\ name=\"([^\"]*)\".*/\1/" | sed -s "s/\..*//"`
names=`geni-get manifest| xmlstarlet fo | xmlstarlet sel -B -t -c "//_:node" | sed -r 's/<node/\n<node/g' | sed -r "s/.*host\ name=\"([^\"]*)\".*/\1/" | sed -s "s/\..*//"`

echo "$names" | while read line ; do
  echo "Bootstrapping $line"
  knife bootstrap "$line" -N "$line"
done

# --------------------------
# Notify the owner via email
echo -e "Dear User,\n\nChef 12 should be installed on `hostname` now. \
Installation log can be found in: /var/log/init-chef.log \
To explore the web console, copy this hostname and paste it into your browser. \
To authenticate, use credentials saved in $CREDS.\n\n\
Happy automation with Chef! For more information, use resources at: http://docs.chef.io/" |  mail -s "Chef 12 Is Deployed" ${SWAPPER_EMAIL} &
