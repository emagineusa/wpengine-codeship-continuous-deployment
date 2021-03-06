#!/bin/bash
# If any commands fail (exit code other than 0) entire script exits
set -e

# Check for required environment variables and make sure they are setup
: ${PROJECT_TYPE?"PROJECT_TYPE Missing"}   # theme|plugin
: ${WPE_ENV_PROD?"WPE_ENV_PROD Missing"}   # subdomain for wpengine install 
: ${WPE_ENV_STAGE?"WPE_ENV_STAGE Missing"} # subdomain for wpengine install 
: ${WPE_ENV_DEV?"WPE_ENV_DEV Missing"}     # subdomain for wpengine install 
: ${REPO_NAME?"REPO_NAME Missing"}         # repo name (Typically the folder name of the project)

# Change the target install based on the branch being pushed.
# master  -> production
# stage   -> staging
# develop -> dev
if [ "$CI_BRANCH" == "master" ] || [ "$CI_BRANCH" == "main" ]
then
    target_wpe_install=${WPE_ENV_PROD}
elif [ "$CI_BRANCH" == "stage" ] || [ "$CI_BRANCH" == "staging" ]
then
	target_wpe_install=${WPE_ENV_STAGE}
else
    target_wpe_install=${WPE_ENV_DEV}
fi

# Begin from the ~/clone directory
# this directory is the default your git project is checked out into by Codeship.
cd ~/clone

if [[ -z "${INCLUDE_ONLY}" ]];
then
	# Get official list of files/folders that are not meant to be on production if $EXCLUDE_LIST is not set.
	if [[ -z "${EXCLUDE_LIST}" ]];
	then
		wget https://raw.githubusercontent.com/linchpin/wpengine-codeship-continuous-deployment/master/exclude-list.txt
	else
		# @todo validate proper url?
		wget ${EXCLUDE_LIST}
	fi

	# Loop over list of files/folders and remove them from deployment
	ITEMS=`cat exclude-list.txt`
	for ITEM in $ITEMS; do
		if [[ $ITEM == *.* ]]
		then
			find . -depth -name "$ITEM" -type f -exec rm "{}" \;
		else
			find . -depth -name "$ITEM" -type d -exec rm -rf "{}" \;
		fi
	done

	# Remove exclude-list file
	rm exclude-list.txt
fi

# Clone the WPEngine files to the deployment directory
# if we are not force pushing our changes
if [[ $CI_MESSAGE != *#force* ]]
then
    force=''
    git clone git@git.wpengine.com:production/${target_wpe_install}.git ~/deployment
else
    force='-f'
    if [ ! -d "~/deployment" ]; then
        mkdir ~/deployment
        cd ~/deployment
        git init
    fi
fi

# If there was a problem cloning, exit
if [ "$?" != "0" ] ; then
    echo "Unable to clone production in ${target_wpe_install}"
    kill -SIGINT $$
fi

# Move the gitignore file to the deployments folder
cd ~/deployment
wget --output-document=.gitignore https://raw.githubusercontent.com/linchpin/wpengine-codeship-continuous-deployment/master/gitignore-template.txt

# Delete plugin/theme if it exists, and move cleaned version into deployment folder
rm -rf /wp-content/${PROJECT_TYPE}s/${REPO_NAME}

# Check to see if the wp-content directory exists, if not create it
if [ ! -d "./wp-content" ]; then
    mkdir ./wp-content
fi
# Check to see if the plugins directory exists, if not create it
if [ ! -d "./wp-content/plugins" ]; then
    mkdir ./wp-content/plugins
fi
# Check to see if the themes directory exists, if not create it
if [ ! -d "./wp-content/themes" ]; then
    mkdir ./wp-content/themes
fi

if [[ -z "${INCLUDE_ONLY}" ]];
then
	clone_directory="../clone/"
else
	clone_directory="../clone/${INCLUDE_ONLY}/"
fi

rsync -a ${clone_directory}* ./wp-content/${PROJECT_TYPE}s/${REPO_NAME}

# Stage, commit, and push to wpengine repo

echo "Add remote"

git remote add production git@git.wpengine.com:production/${target_wpe_install}.git

git config --global user.email CI_COMMITTER_EMAIL
git config --global user.name CI_COMMITTER_NAME
git config core.ignorecase false
git add --all
git commit -am "Deployment to ${target_wpe_install} production by $CI_COMMITTER_NAME from $CI_NAME"

git push ${force} production master
