#!/usr/bin/env bats

setup() {
  DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
  PATH="$DIR/../src:$PATH"
  export GITHUB_OUTPUT=${BATS_TEST_TMPDIR}/github_output
  touch ${GITHUB_OUTPUT}
  touch metadata_tmp
}

teardown() {
  rm -f metadata_tmp
  unset GITHUB_OUTPUT
}

@test "fail when SONAR_TOKEN not provided" {
  run script/check-quality-gate.sh
  [ "$status" -eq 1 ]
  [ "$output" = "Set the SONAR_TOKEN env variable." ]
}

@test "use URL from SONAR_HOST_URL instead of metadata file when it is provided" {
  export SONAR_TOKEN="test"
  export SONAR_HOST_URL="http://sonarqube.org/" # Add a trailing slash, so we validate it correctly removes it.
  echo "serverUrl=http://localhost:9000" >> metadata_tmp
  echo "ceTaskUrl=http://localhost:9000/api/ce/task?id=AXlCe3gsFwOUsY8YKHTn" >> metadata_tmp

  #mock curl
  function curl() {
    url="${@: -1}"
    if [[ $url == "http://localhost:9000/"* ]]; then
      echo '{"error":["Not found"]}'
    elif [[ $url == "http://sonarqube.org/api/qualitygates/project_status?analysisId"* ]]; then
      echo '{"projectStatus":{"status":"OK"}}'
    else
      echo '{"task":{"analysisId":"AXlCe3jz9LkwR9Gs0pBY","status":"SUCCESS"}}'
    fi
  }
  export -f curl

  run script/check-quality-gate.sh metadata_tmp 300
  [ "$status" -eq 0 ]
}

@test "fail when metadata file not exist" {
  rm -f metadata_tmp
  export SONAR_TOKEN="test"
  run script/check-quality-gate.sh
  [ "$status" -eq 1 ]
  [ "$output" = " does not exist." ]
}

@test "fail when empty metadata file" {
  export SONAR_TOKEN="test"
  run script/check-quality-gate.sh metadata_tmp 300
  [ "$status" -eq 1 ]
  [ "$output" = "Invalid report metadata file." ]
}

@test "fail when no polling timeout is provided" {
  export SONAR_TOKEN="test"
  run script/check-quality-gate.sh metadata_tmp
  [ "$status" -eq 1 ]
  [ "$output" = "'' is an invalid value for the polling timeout. Please use a positive, non-zero number." ]
}

@test "fail when polling timeout is not a number" {
  export SONAR_TOKEN="test"
  run script/check-quality-gate.sh metadata_tmp metadata_tmp
  [ "$status" -eq 1 ]
  [ "$output" = "'metadata_tmp' is an invalid value for the polling timeout. Please use a positive, non-zero number." ]
}

@test "fail when polling timeout is zero" {
  export SONAR_TOKEN="test"
  run script/check-quality-gate.sh metadata_tmp 0
  [ "$status" -eq 1 ]
  [ "$output" = "'0' is an invalid value for the polling timeout. Please use a positive, non-zero number." ]
}

@test "fail when polling timeout is negative" {
  export SONAR_TOKEN="test"
  run script/check-quality-gate.sh metadata_tmp -1
  [ "$status" -eq 1 ]
  [ "$output" = "'-1' is an invalid value for the polling timeout. Please use a positive, non-zero number." ]
}

@test "fail when no Quality Gate status" {
  export SONAR_TOKEN="test"
  echo "serverUrl=http://localhost:9000" >> metadata_tmp
  echo "ceTaskUrl=http://localhost:9000/api/ce/task?id=AXlCe3gsFwOUsY8YKHTn" >> metadata_tmp

  #mock curl
  function curl() {
     echo '{"task":{"analysisId":"AXlCe3jz9LkwR9Gs0pBY","status":"SUCCESS"}}'
  }
  export -f curl

  run script/check-quality-gate.sh metadata_tmp 300

  read -r github_out_actual < ${GITHUB_OUTPUT}

  [ "$status" -eq 1 ]
  [[ "${github_out_actual}" = "quality-gate-status=FAILED" ]]
  [[ "$output" = *"Quality Gate not set for the project. Please configure the Quality Gate in SonarQube or remove sonarqube-quality-gate action from the workflow."* ]]
}

@test "fail when polling timeout is reached" {
  export SONAR_TOKEN="test"
  echo "serverUrl=http://localhost:9000" >> metadata_tmp
  echo "ceTaskUrl=http://localhost:9000/api/ce/task?id=AXlCe3jz9LkwR9Gs0pBY" >> metadata_tmp

  #mock curl
  function curl() {
     echo '{"task":{"analysisId":"AXlCe3jz9LkwR9Gs0pBY","status":"PENDING"}}'
  }
  export -f curl

  run script/check-quality-gate.sh metadata_tmp 5

  [ "$status" -eq 1 ]
  [[ "$output" = *"Polling timeout reached for waiting for finishing of the Sonar scan! Aborting the check for SonarQube's Quality Gate."* ]]
}

@test "fail when Quality Gate status WARN" {
  export SONAR_TOKEN="test"
  echo "serverUrl=http://localhost:9000" >> metadata_tmp
  echo "ceTaskUrl=http://localhost:9000/api/ce/task?id=AXlCe3gsFwOUsY8YKHTn" >> metadata_tmp
  echo "dashboardUrl=http://localhost:9000/dashboard?id=project&branch=master" >> metadata_tmp

  #mock curl
  function curl() {
    url="${@: -1}"
     if [[ $url == *"/api/qualitygates/project_status?analysisId"* ]]; then
       echo '{"projectStatus":{"status":"WARN"}}'
     else
       echo '{"task":{"analysisId":"AXlCe3jz9LkwR9Gs0pBY","status":"SUCCESS"}}'
     fi
  }
  export -f curl

  run script/check-quality-gate.sh metadata_tmp 300

  read -r github_out_actual < ${GITHUB_OUTPUT}

  [ "$status" -eq 1 ]
  [[ "${github_out_actual}" = "quality-gate-status=WARN" ]]
  [[ "$output" = *"Warnings on Quality Gate."* ]]
  [[ "$output" = *"Detailed information can be found at: http://localhost:9000/dashboard?id=project&branch=master"* ]]
}

@test "fail when Quality Gate status ERROR" {
  export SONAR_TOKEN="test"
  echo "serverUrl=http://localhost:9000" >> metadata_tmp
  echo "ceTaskUrl=http://localhost:9000/api/ce/task?id=AXlCe3gsFwOUsY8YKHTn" >> metadata_tmp
  echo "dashboardUrl=http://localhost:9000/dashboard?id=project&branch=master" >> metadata_tmp

  #mock curl
  function curl() {
    url="${@: -1}"
     if [[ $url == *"/api/qualitygates/project_status?analysisId"* ]]; then
       echo '{"projectStatus":{"status":"ERROR"}}'
     else
       echo '{"task":{"analysisId":"AXlCe3jz9LkwR9Gs0pBY","status":"SUCCESS"}}'
     fi
  }
  export -f curl

  run script/check-quality-gate.sh metadata_tmp 300

  read -r github_out_actual < ${GITHUB_OUTPUT}

  [ "$status" -eq 1 ]
  [[ "${github_out_actual}" = "quality-gate-status=FAILED" ]]
  [[ "$output" = *"Quality Gate has FAILED."* ]]
  [[ "$output" = *"Detailed information can be found at: http://localhost:9000/dashboard?id=project&branch=master"* ]]
}

@test "pass when Quality Gate status OK" {
  export SONAR_TOKEN="test"
  echo "serverUrl=http://localhost:9000" >> metadata_tmp
  echo "ceTaskUrl=http://localhost:9000/api/ce/task?id=AXlCe3gsFwOUsY8YKHTn" >> metadata_tmp

  #mock curl
  function curl() {
    url="${@: -1}"
     if [[ $url == *"/api/qualitygates/project_status?analysisId"* ]]; then
       echo '{"projectStatus":{"status":"OK"}}'
     else
       echo '{"task":{"analysisId":"AXlCe3jz9LkwR9Gs0pBY","status":"SUCCESS"}}'
     fi
  }
  export -f curl

  run script/check-quality-gate.sh metadata_tmp 300

  read -r github_out_actual < ${GITHUB_OUTPUT}

  [ "$status" -eq 0 ]
  [[ "${github_out_actual}" = "quality-gate-status=PASSED" ]]
  [[ "$output" = *"Quality Gate has PASSED."* ]]
  [[ "$output" != *"Detailed information can be found at:"* ]]
}

@test "pass when Quality Gate status OK and status starts from IN_PROGRESS" {
  export SONAR_TOKEN="test"
  export COUNTER_FILE=${BATS_TEST_TMPDIR}/counter
  echo "serverUrl=http://localhost:9000" >> metadata_tmp
  echo "ceTaskUrl=http://localhost:9000/api/ce/task?id=AXlCe3gsFwOUsY8YKHTn" >> metadata_tmp

  printf "5" > ${COUNTER_FILE}

  #mock curl
  function curl() {
    read -r counter < ${COUNTER_FILE}

    url="${@: -1}"
     if [[ $url == *"/api/qualitygates/project_status?analysisId"* ]]; then
       echo '{"projectStatus":{"status":"OK"}}'
     elif [[ $counter -gt 0 ]]; then
       echo '{"task":{"analysisId":"AXlCe3jz9LkwR9Gs0pBY","status":"IN_PROGRESS"}}'
       printf "%d\n" "$(( --counter ))" > ${COUNTER_FILE}
     else
       echo '{"task":{"analysisId":"AXlCe3jz9LkwR9Gs0pBY","status":"SUCCESS"}}'
     fi
  }
  export -f curl

  #mock sleep
  function sleep() {
    return 0
  }
  export -f sleep

  run script/check-quality-gate.sh metadata_tmp 300

  read -r github_out_actual < ${GITHUB_OUTPUT}

  [ "$status" -eq 0 ]
  [[ "${github_out_actual}" = "quality-gate-status=PASSED" ]]
  # lines[0] is the dots from waiting for status to move to SUCCESS
  [[ "${lines[0]}" = "....." ]]
  [[ "${lines[1]}" = *"Quality Gate has PASSED."* ]]
}

@test "pass spaces in GITHUB_OUTPUT path are handled" {
  export SONAR_TOKEN="test"
  echo "serverUrl=http://localhost:9000" >> metadata_tmp
  echo "ceTaskUrl=http://localhost:9000/api/ce/task?id=AXlCe3gsFwOUsY8YKHTn" >> metadata_tmp

  #mock curl
  function curl() {
    url="${@: -1}"
     if [[ $url == *"/api/qualitygates/project_status?analysisId"* ]]; then
       echo '{"projectStatus":{"status":"OK"}}'
     else
       echo '{"task":{"analysisId":"AXlCe3jz9LkwR9Gs0pBY","status":"SUCCESS"}}'
     fi
  }
  export -f curl

  # GITHUB_OUTPUT is a path with spaces
  github_output_dir="${BATS_TEST_TMPDIR}/some subdir"
  mkdir -p "${github_output_dir}"
  export GITHUB_OUTPUT="${github_output_dir}/github_output"
  touch "${GITHUB_OUTPUT}"

  run script/check-quality-gate.sh metadata_tmp 300

  read -r github_out_actual < "${GITHUB_OUTPUT}"

  [ "$status" -eq 0 ]
  [[ "${github_out_actual}" = "quality-gate-status=PASSED" ]]
  [[ "$output" = *"Quality Gate has PASSED."* ]]
}

@test "pass fall back to set-output if GITHUB_OUTPUT unset" {
  export SONAR_TOKEN="test"
  unset GITHUB_OUTPUT
  echo "serverUrl=http://localhost:9000" >> metadata_tmp
  echo "ceTaskUrl=http://localhost:9000/api/ce/task?id=AXlCe3gsFwOUsY8YKHTn" >> metadata_tmp

  #mock curl
  function curl() {
    url="${@: -1}"
     if [[ $url == *"/api/qualitygates/project_status?analysisId"* ]]; then
       echo '{"projectStatus":{"status":"OK"}}'
     else
       echo '{"task":{"analysisId":"AXlCe3jz9LkwR9Gs0pBY","status":"SUCCESS"}}'
     fi
  }
  export -f curl

  run script/check-quality-gate.sh metadata_tmp 300

  [ "$status" -eq 0 ]
  [[ "$output" = *"::set-output name=quality-gate-status::PASSED"* ]]
  [[ "$output" = *"Quality Gate has PASSED."* ]]
}

@test "generate quality gate summary when dashboard URL contains project info" {
  export SONAR_TOKEN="test"
  echo "serverUrl=https://sonarcloud.io" >> metadata_tmp
  echo "ceTaskUrl=https://sonarcloud.io/api/ce/task?id=AXlCe3gsFwOUsY8YKHTn" >> metadata_tmp
  echo "dashboardUrl=https://sonarcloud.io/project/overview?id=test-project&pullRequest=42" >> metadata_tmp

  #mock curl
  function curl() {
    local url="${@: -1}"
    if [[ $url == *"/api/qualitygates/project_status?analysisId"* ]]; then
      echo '{"projectStatus":{"status":"OK"}}'
    elif [[ $url == *"/api/issues/search"* && $url == *"sinceLeakPeriod=true"* ]]; then
      echo '{"total":3}'  # New issues
    elif [[ $url == *"/api/issues/search"* && $url == *"issueStatuses=ACCEPTED"* ]]; then
      echo '{"total":1}'  # Accepted issues
    elif [[ $url == *"/api/hotspots/search"* ]]; then
      echo '{"paging":{"total":2}}'  # Security hotspots
    elif [[ $url == *"/api/measures/component"* && $url == *"new_coverage"* ]]; then
      echo '{"component":{"measures":[{"value":"85.5"}]}}'  # Coverage
    elif [[ $url == *"/api/measures/component"* && $url == *"new_duplicated_lines_density"* ]]; then
      echo '{"component":{"measures":[{"value":"1.2"}]}}'  # Duplication
    else
      echo '{"task":{"analysisId":"AXlCe3jz9LkwR9Gs0pBY","status":"SUCCESS"}}'
    fi
  }
  export -f curl

  run script/check-quality-gate.sh metadata_tmp 300

  # Check both quality-gate-status and quality_gate_summary outputs
  local github_output_content
  github_output_content=$(cat ${GITHUB_OUTPUT})

  [ "$status" -eq 0 ]
  
  # Check quality-gate-status output
  [[ "$github_output_content" = *"quality-gate-status=PASSED"* ]]
  
  # Check quality-gate-summary output exists (multiline format)
  [[ "$github_output_content" = *"quality-gate-summary<<"* ]]
  [[ "$github_output_content" = *"Quality Gate Passed"* ]]
  [[ "$github_output_content" = *"[3 New issues]"* ]]
  [[ "$github_output_content" = *"[1 Accepted issues]"* ]]
  [[ "$github_output_content" = *"[2 Security Hotspots]"* ]]
  [[ "$github_output_content" = *"[85.5% Coverage on New Code]"* ]]
  [[ "$github_output_content" = *"[1.2% Duplication on New Code]"* ]]
  
  # Check console output
  [[ "$output" = *"Quality Gate has PASSED."* ]]
  [[ "$output" = *"Quality Gate Passed"* ]]
  [[ "$output" = *"[3 New issues]"* ]]
  [[ "$output" = *"[1 Accepted issues]"* ]]
  [[ "$output" = *"[2 Security Hotspots]"* ]]
  [[ "$output" = *"[85.5% Coverage on New Code]"* ]]
  [[ "$output" = *"[1.2% Duplication on New Code]"* ]]
  [[ "$output" = *"pullRequest=42"* ]]
}

@test "use slack format when SLACK_FORMAT is true" {
  export SONAR_TOKEN="test"
  export SLACK_FORMAT="true"
  echo "serverUrl=http://localhost:9000" >> metadata_tmp
  echo "ceTaskUrl=http://localhost:9000/api/ce/task?id=AXlCe3gsFwOUsY8YKHTn" >> metadata_tmp
  echo "dashboardUrl=http://localhost:9000/dashboard?id=project&branch=master" >> metadata_tmp

  #mock curl for different API calls
  function curl() {
    url="${@: -1}"
    if [[ $url == *"/api/qualitygates/project_status?analysisId"* ]]; then
      echo '{"projectStatus":{"status":"OK"}}'
    elif [[ $url == *"/api/issues/search"* ]]; then
      if [[ $url == *"sinceLeakPeriod=true"* ]]; then
        echo '{"total":3}'
      else
        echo '{"total":1}'
      fi
    elif [[ $url == *"/api/hotspots/search"* ]]; then
      echo '{"paging":{"total":2}}'
    elif [[ $url == *"/api/measures/component"* ]]; then
      if [[ $url == *"new_coverage"* ]]; then
        echo '{"component":{"measures":[{"value":"85.5"}]}}'
      else
        echo '{"component":{"measures":[{"value":"1.2"}]}}'
      fi
    else
      echo '{"task":{"analysisId":"AXlCe3jz9LkwR9Gs0pBY","status":"SUCCESS"}}'
    fi
  }
  export -f curl

  run script/check-quality-gate.sh metadata_tmp 300

  [ "$status" -eq 0 ]
  # Check that Slack format is used (with <url|text> syntax and *bold* headers)
  [[ "$output" = *"Quality Gate Passed"* ]]
  [[ "$output" = *"*Issues*"* ]]
  [[ "$output" = *"*Measures*"* ]]
  [[ "$output" = *"<http://localhost:9000/project/issues"*"|3 New issues>"* ]]
  [[ "$output" = *"<http://localhost:9000/project/issues"*"|1 Accepted issues>"* ]]
  [[ "$output" = *"<http://localhost:9000/project/security_hotspots"*"|2 Security Hotspots>"* ]]
  [[ "$output" = *"<http://localhost:9000/component_measures"*"|85.5% Coverage on New Code>"* ]]
  [[ "$output" = *"<http://localhost:9000/component_measures"*"|1.2% Duplication on New Code>"* ]]
}

@test "use markdown format when SLACK_FORMAT is false or unset" {
  export SONAR_TOKEN="test"
  # SLACK_FORMAT not set, should default to markdown
  echo "serverUrl=http://localhost:9000" >> metadata_tmp
  echo "ceTaskUrl=http://localhost:9000/api/ce/task?id=AXlCe3gsFwOUsY8YKHTn" >> metadata_tmp
  echo "dashboardUrl=http://localhost:9000/dashboard?id=project&branch=master" >> metadata_tmp

  #mock curl for different API calls
  function curl() {
    url="${@: -1}"
    if [[ $url == *"/api/qualitygates/project_status?analysisId"* ]]; then
      echo '{"projectStatus":{"status":"OK"}}'
    elif [[ $url == *"/api/issues/search"* ]]; then
      if [[ $url == *"sinceLeakPeriod=true"* ]]; then
        echo '{"total":3}'
      else
        echo '{"total":1}'
      fi
    elif [[ $url == *"/api/hotspots/search"* ]]; then
      echo '{"paging":{"total":2}}'
    elif [[ $url == *"/api/measures/component"* ]]; then
      if [[ $url == *"new_coverage"* ]]; then
        echo '{"component":{"measures":[{"value":"85.5"}]}}'
      else
        echo '{"component":{"measures":[{"value":"1.2"}]}}'
      fi
    else
      echo '{"task":{"analysisId":"AXlCe3jz9LkwR9Gs0pBY","status":"SUCCESS"}}'
    fi
  }
  export -f curl

  run script/check-quality-gate.sh metadata_tmp 300

  [ "$status" -eq 0 ]
  # Check that markdown format is used (with [text](url) syntax and regular headers)
  [[ "$output" = *"Quality Gate Passed"* ]]
  [[ "$output" = *"Issues"* ]]
  [[ "$output" = *"Measures"* ]]
  [[ "$output" = *"[3 New issues](http://localhost:9000/project/issues"* ]]
  [[ "$output" = *"[1 Accepted issues](http://localhost:9000/project/issues"* ]]
  [[ "$output" = *"[2 Security Hotspots](http://localhost:9000/project/security_hotspots"* ]]
  [[ "$output" = *"[85.5% Coverage on New Code](http://localhost:9000/component_measures"* ]]
  [[ "$output" = *"[1.2% Duplication on New Code](http://localhost:9000/component_measures"* ]]
  # Ensure it's NOT using Slack format
  [[ "$output" != *"*Issues*"* ]]
  [[ "$output" != *"*Measures*"* ]]
  [[ "$output" != *"<http"*"|"*">"* ]]
}
