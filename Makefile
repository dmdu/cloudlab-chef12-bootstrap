build : chef-install.sh chef-run.sh ssh-find-agent.sh 
	tar czvf chef12-scripts-dev.tar.gz chef-install.sh chef-run.sh ssh-find-agent.sh

upload: chef12-scripts-dev.tar.gz
	aws s3 cp chef12-scripts-dev.tar.gz s3://dmdu-cloudlab/ --grants read=uri=http://acs.amazonaws.com/groups/global/AllUsers

clean :
	rm chef12-scripts-dev.tar.gz
