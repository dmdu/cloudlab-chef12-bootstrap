#!/bin/bash

# This script calls the install script with file logging
# Author: Dmitry Duplyakin
# Date: 06/10/15

# Proper way to call the install script
/bin/bash /root/chef-install.sh >> /var/log/init-chef.log 2>&1

