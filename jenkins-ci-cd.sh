#!/bin/bash

# Default values
WAIT_FOR_COMPLETION=true
FAIL_ON_NEW_LEAKS=true

# Parse the input arguments
TEMP=$(getopt -n "$0" -a -l "hostname:,username:,password:,catalog-id:,wait-for-completion:,fail-on-new-leaks:,api-name:" -- -- "$@")

[ $? -eq 0 ] || exit

eval set -- "$TEMP"

while [ $# -gt 0 ]
do
    case "$1" in
        --hostname) PERFAI_HOSTNAME="$2"; shift;;
        --username) PERFAI_USERNAME="$2"; shift;;
        --password) PERFAI_PASSWORD="$2"; shift;;
        --catalog-id) CATALOG_ID="$2"; shift;;
        --wait-for-completion) WAIT_FOR_COMPLETION="$2"; shift;;
        --fail-on-new-leaks) FAIL_ON_NEW_LEAKS="$2"; shift;;
        --api-name) API_NAME="$2"; shift;;
        --) shift ;;
    esac
    shift;
done

echo " "

if [ "$PERFAI_HOSTNAME" = "" ];
then
PERFAI_HOSTNAME="https://app.apiprivacy.com"
fi

### Step 1: Print Access Token ###
TOKEN_RESPONSE=$(curl -s --location --request POST "https://api.perfai.ai/api/v1/auth/token" \
--header "Content-Type: application/json" \
--data-raw "{
    \"username\": \"${PERFAI_USERNAME}\",
    \"password\": \"${PERFAI_PASSWORD}\"
}")

ACCESS_TOKEN=$(echo $TOKEN_RESPONSE | jq -r '.id_token')

if [ -z "$ACCESS_TOKEN" ]; then
    echo "Error: Could not retrieve access token"
    exit 1
fi

echo "Access Token is: $ACCESS_TOKEN"
echo " "


### Step 2: Trigger the AI Running ###
RUN_RESPONSE=$(curl -s --location --request POST "https://api.perfai.ai/api/v1/api-catalog/apps/schedule-run-multiple" \
--header "Content-Type: application/json" \
--header "Authorization: Bearer $ACCESS_TOKEN" \
--data-raw "{
    \"catalog_id\": \"${CATALOG_ID}\",
    \"services\": [\"sensitive\"]
}")

# Get commit information from Jenkins environment variables
# COMMIT_ID=${GIT_COMMIT}
# COMMIT_DATE=$(date "+%F")  # Assuming you want the current date for commit date
# COMMIT_URL="https://github.com/${GIT_URL##*/}/commit/${COMMIT_ID}"  # Build commit URL from GIT_URL and COMMIT_ID

# # You can also use GIT_AUTHOR_NAME or GIT_COMMITTER_NAME for author information
# COMMIT_USER=${GIT_AUTHOR_NAME}
# REPO_NAME=$(basename -s .git ${GIT_URL})

# echo "Commit ID: $COMMIT_ID"
# echo "Commit Date: $COMMIT_DATE"
# echo "Commit URL: $COMMIT_URL"
# echo "Commit User: $COMMIT_USER"
# echo "Repository Name: $REPO_NAME"

# # Step 2: Schedule API Privacy Tests
# RUN_RESPONSE=$(curl -s --location --request POST https://api.perfai.ai/api/v1/api-catalog/apps/schedule-run-multiple \
#   -H "Content-Type: application/json" \
#   -H "Authorization: Bearer $ACCESS_TOKEN" \
#   -d "{
#     \"catalog_id\": \"${CATALOG_ID}\",
#     \"services\": [\"sensitive\"],
#     \"buildDetails\": {
#         \"commitId\": \"${COMMIT_ID}\",
#         \"commitUrl\": \"${COMMIT_URL}\",
#         \"commitUserName\": \"${COMMIT_USER}\",
#         \"commitDate\": \"${COMMIT_DATE}\",
#         \"repoName\": \"${REPO_NAME}\"
#     }
#   }"
# )


#echo "Run Response: $RUN_RESPONSE"

### RUN_ID Prints ###
RUN_ID=$(echo "$RUN_RESPONSE" | jq -r '.run_ids.sensitive')

# Output Run Response ###
echo " "
echo "Run Response: $RUN_RESPONSE"
echo " "
echo "Run ID is: $RUN_ID"

if [ -z "$RUN_ID" ]; then
  echo "Error: Run ID not found in the response"
  exit 1
fi

### Step 3: Check the wait-for-completion flag ###
if [ "$WAIT_FOR_COMPLETION" == "true" ]; then
    echo "Waiting for API Privacy Tests to complete..."

    STATUS="PROCESSING"

    ### Step 4: Poll the status of the AI run until completion ###
    while [[ "$STATUS" == "PROCESSING" ]]; do
        
        # Check the status of the API Privacy Tests
    STATUS_RESPONSE=$(curl -s --location --request GET "https://api.perfai.ai/api/v1/sensitive-data-service/apps/get-run-status?run_id=$RUN_ID" \
      --header "Authorization: Bearer $ACCESS_TOKEN")    
    
    STATUS=$(echo "$STATUS_RESPONSE" | jq -r '.status')
    
    if  [ "$STATUS" == "COMPLETED"  ]; then

    NEW_ISSUES=$(echo "$STATUS_RESPONSE" | jq -r '.newIssues[]')
    NEW_ISSUES_DETECTED=$(echo "$STATUS_RESPONSE" | jq -r '.newIssuesDetected')

    echo " "
    echo "AI Running Status: $(echo "$STATUS_RESPONSE" | jq)"

    # If the run completes and fail-on-new-leaks is enabled
        if [ "$NEW_ISSUES_DETECTED" = false ]; then
          echo "No new issues detected. Build passed."
        else 
          echo "Build failed with new issues. New issue: $NEW_ISSUES"
          exit 1
        fi
    fi 

    # If the AI run fails, exit with an error
    if [[ "$NEW_ISSUES_DETECTED" == "failed" ]]; then
      echo "Error: API Privacy Tests failed for Run ID $RUN_ID"
      exit 1
    fi
  done
    
    # Once the status is no longer "in_progress", assume it completed
   echo "API Privacy Tests for API ID $CATALOG_ID has completed successfully!"
 else
   echo "API Privacy Tests triggered. Run ID: $RUN_ID. Exiting without waiting for completion."
   exit 1  
 fi
