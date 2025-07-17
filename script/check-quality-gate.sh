#!/usr/bin/env bash

source "$(dirname "$0")/common.sh"

if [[ -z "${SONAR_TOKEN}" ]]; then
  echo "Set the SONAR_TOKEN env variable."
  exit 1
fi

metadataFile="$1"
pollingTimeoutSec="$2"


if [[ ! -f "$metadataFile" ]]; then
   echo "$metadataFile does not exist."
   exit 1
fi

if [[ ! $pollingTimeoutSec =~ ^[0-9]+$ || $pollingTimeoutSec -le 0 ]]; then
   echo "'$pollingTimeoutSec' is an invalid value for the polling timeout. Please use a positive, non-zero number."
   exit 1
fi

if [[ ! -z "${SONAR_HOST_URL}" ]]; then
   serverUrl="${SONAR_HOST_URL%/}"
   ceTaskUrl="${SONAR_HOST_URL%/}/api$(sed -n 's/^ceTaskUrl=.*api//p' "${metadataFile}")"
else
   serverUrl="$(sed -n 's/serverUrl=\(.*\)/\1/p' "${metadataFile}")"
   ceTaskUrl="$(sed -n 's/ceTaskUrl=\(.*\)/\1/p' "${metadataFile}")"
fi

if [ -z "${serverUrl}" ] || [ -z "${ceTaskUrl}" ]; then
  echo "Invalid report metadata file."
  exit 1
fi

if [[ -n "${SONAR_ROOT_CERT}" ]]; then
  echo "Adding custom root certificate to ~/.curlrc"
  rm -f /tmp/tmpcert.pem
  echo "${SONAR_ROOT_CERT}" > /tmp/tmpcert.pem
  echo "--cacert /tmp/tmpcert.pem" >> ~/.curlrc
fi

task="$(curl --location --location-trusted --max-redirs 10  --silent --fail --show-error --user "${SONAR_TOKEN}": "${ceTaskUrl}")"
status="$(jq -r '.task.status' <<< "$task")"

endTime=$(( ${SECONDS} + ${pollingTimeoutSec} ))

until [[ ${status} != "PENDING" && ${status} != "IN_PROGRESS" || ${SECONDS} -ge ${endTime} ]]; do
    printf '.'
    sleep 5
    task="$(curl --location --location-trusted --max-redirs 10 --silent --fail --show-error --user "${SONAR_TOKEN}": "${ceTaskUrl}")"
    status="$(jq -r '.task.status' <<< "$task")"
done
printf '\n'

if [[ ${status} == "PENDING" || ${status} == "IN_PROGRESS" ]] && [[ ${SECONDS} -ge ${endTime} ]]; then
    echo "Polling timeout reached for waiting for finishing of the Sonar scan! Aborting the check for SonarQube's Quality Gate."
    exit 1
fi

analysisId="$(jq -r '.task.analysisId' <<< "${task}")"
qualityGateUrl="${serverUrl}/api/qualitygates/project_status?analysisId=${analysisId}"
qualityGateStatus="$(curl --location --location-trusted --max-redirs 10 --silent --fail --show-error --user "${SONAR_TOKEN}": "${qualityGateUrl}" | jq -r '.projectStatus.status')"

dashboardUrl="$(sed -n 's/dashboardUrl=\(.*\)/\1/p' "${metadataFile}")"
analysisResultMsg="Detailed information can be found at: ${dashboardUrl}\n"

# Extract project information for quality gate summary
extract_project_info() {
  # Extract project key from dashboard URL
  if [[ $dashboardUrl =~ id=([^&]+) ]]; then
    projectKey="${BASH_REMATCH[1]}"
  else
    projectKey=""
  fi
  
  # Extract pull request number if present
  if [[ $dashboardUrl =~ pullRequest=([^&]+) ]]; then
    pullRequest="${BASH_REMATCH[1]}"
  else
    pullRequest=""
  fi
  
  # Extract branch if present and no PR
  if [[ $dashboardUrl =~ branch=([^&]+) ]] && [[ -z $pullRequest ]]; then
    branch="${BASH_REMATCH[1]}"
  else
    branch=""
  fi
}

# Function to get issues count
get_issues_count() {
  local issue_type="$1"  # "new" or "accepted"
  local api_url
  local params="componentKeys=${projectKey}"
  
  if [[ -n $pullRequest ]]; then
    params="${params}&pullRequest=${pullRequest}"
  elif [[ -n $branch ]]; then
    params="${params}&branch=${branch}"
  fi
  
  if [[ $issue_type == "new" ]]; then
    params="${params}&sinceLeakPeriod=true&issueStatuses=OPEN,CONFIRMED"
  elif [[ $issue_type == "accepted" ]]; then
    params="${params}&issueStatuses=ACCEPTED"
  fi
  
  api_url="${serverUrl}/api/issues/search?${params}&ps=1"
  
  local response
  response="$(curl --location --location-trusted --max-redirs 10 --silent --fail --show-error --user "${SONAR_TOKEN}": "${api_url}" 2>/dev/null || echo '{"total":0}')"
  echo "$(jq -r '.total // 0' <<< "$response")"
}

# Function to get security hotspots count
get_security_hotspots_count() {
  local params="projectKey=${projectKey}"
  
  if [[ -n $pullRequest ]]; then
    params="${params}&pullRequest=${pullRequest}"
  elif [[ -n $branch ]]; then
    params="${params}&branch=${branch}"
  fi
  
  params="${params}&sinceLeakPeriod=true&status=TO_REVIEW"
  
  local api_url="${serverUrl}/api/hotspots/search?${params}&ps=1"
  
  local response
  response="$(curl --location --location-trusted --max-redirs 10 --silent --fail --show-error --user "${SONAR_TOKEN}": "${api_url}" 2>/dev/null || echo '{"paging":{"total":0}}')"
  echo "$(jq -r '.paging.total // 0' <<< "$response")"
}

# Function to get measures
get_measure() {
  local metric="$1"
  local params="component=${projectKey}&metricKeys=${metric}"
  
  if [[ -n $pullRequest ]]; then
    params="${params}&pullRequest=${pullRequest}"
  elif [[ -n $branch ]]; then
    params="${params}&branch=${branch}"
  fi
  
  local api_url="${serverUrl}/api/measures/component?${params}"
  
  local response
  response="$(curl --location --location-trusted --max-redirs 10 --silent --fail --show-error --user "${SONAR_TOKEN}": "${api_url}" 2>/dev/null || echo '{"component":{"measures":[]}}')"
  echo "$(jq -r '.component.measures[0].value // "0.0"' <<< "$response")"
}

# Function to generate quality gate summary
generate_quality_gate_summary() {
  extract_project_info
  
  if [[ -z $projectKey ]]; then
    return  # Skip summary if we can't extract project key
  fi
  
  local status_text
  if [[ ${qualityGateStatus} == "OK" ]]; then
    status_text="Quality Gate Passed"
  else
    status_text="Quality Gate Failed"
  fi
  
  local new_issues_count
  local accepted_issues_count
  local security_hotspots_count
  local coverage_value
  local duplication_value
  
  new_issues_count="$(get_issues_count "new")"
  accepted_issues_count="$(get_issues_count "accepted")"
  security_hotspots_count="$(get_security_hotspots_count)"
  coverage_value="$(get_measure "new_coverage")"
  duplication_value="$(get_measure "new_duplicated_lines_density")"
  
  # Build URL parameters
  local url_params="id=${projectKey}"
  if [[ -n $pullRequest ]]; then
    url_params="${url_params}&pullRequest=${pullRequest}"
  elif [[ -n $branch ]]; then
    url_params="${url_params}&branch=${branch}"
  fi
  
  # Generate summary
  echo ""
  echo "$status_text"
  echo "Issues"
  echo " [${new_issues_count} New issues](${serverUrl}/project/issues?${url_params}&issueStatuses=OPEN,CONFIRMED&sinceLeakPeriod=true)"
  echo " [${accepted_issues_count} Accepted issues](${serverUrl}/project/issues?${url_params}&issueStatuses=ACCEPTED)"
  echo ""
  echo "Measures"
  echo " [${security_hotspots_count} Security Hotspots](${serverUrl}/project/security_hotspots?${url_params}&issueStatuses=OPEN,CONFIRMED&sinceLeakPeriod=true)"
  echo " [${coverage_value}% Coverage on New Code](${serverUrl}/component_measures?${url_params}&metric=new_coverage&view=list)"
  echo " [${duplication_value}% Duplication on New Code](${serverUrl}/component_measures?${url_params}&metric=new_duplicated_lines_density&view=list)"
}

if [[ ${qualityGateStatus} == "OK" ]]; then
   set_output "quality-gate-status" "PASSED"
   success "Quality Gate has PASSED."
   generate_quality_gate_summary
elif [[ ${qualityGateStatus} == "WARN" ]]; then
   set_output "quality-gate-status" "WARN"
   generate_quality_gate_summary
   warn "Warnings on Quality Gate.${reset}\n\n${analysisResultMsg}"
elif [[ ${qualityGateStatus} == "ERROR" ]]; then
   set_output "quality-gate-status" "FAILED"
   generate_quality_gate_summary
   fail "Quality Gate has FAILED.${reset}\n\n${analysisResultMsg}"
else
   set_output "quality-gate-status" "FAILED"
   fail "Quality Gate not set for the project. Please configure the Quality Gate in SonarQube or remove sonarqube-quality-gate action from the workflow."
fi

