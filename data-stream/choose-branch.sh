#!/bin/bash

# Get the name of the current Git branch
branch=$(git branch | sed -n -e 's/^* \(.*\)/\1/p')

# Only deploy to production if the current branch is the master branch
if [ "$branch" == "master" ]; then
    echo "Deploying to production..."
    # Add your deployment commands here
elif [[ "$branch" == feature* || "$branch" == dev* ]]; then
    echo "Deploying to develop..."
    # Add your deployment commands here
else
    echo "Not on master or feature/dev branch. Skipping deployment."
fi
