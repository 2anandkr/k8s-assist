#!/usr/bin/env bash

set -e

# Copyright 2020 anand kumar 

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.




function process_args() {
  while [ "$#" -gt "0" ]
  do  
    local key="$1"
    shift
    case $key in
      seal)
        COMMAND="$key"
        ;;
      unseal)
        COMMAND="$key"
        ;;
      --namespace|-n)
        NAMESPACE="$1"
        shift
        ;;
      --secret|-s)
        SECRET="$1"
        shift
        ;;
      --help|-help|-h)
        print_usage
        exit 13
        ;;        
      *)
        echo "ERROR: Unknown argument '$key'"
        exit -1
    esac
  done
}


function run_command() {
  [[ -z "$COMMAND" || -z "$NAMESPACE" || -z "$SECRET" ]] && print_usage && exit 13
  $COMMAND
}


function seal() {  
  local env_file=$SECRET-secret.env
  local sealed_secret_file=$SECRET-sealed-secret.yaml

  # https://gist.github.com/judy2k/7656bfe3b322d669ef75364a46327836#gistcomment-2853823
  # IFS changes what bash splits strings on. By default it splits on spaces, 
  # but using the below it only does so on newlines. 
  # We reset its behavior after we're done.
  IFS='
'  
  # adhere system compatibility for xargs
  uname_str=$(uname)
  if [[ $uname_str == 'Linux' ]]; then
    local env_entries=($(egrep -v '^#' $env_file | xargs -d '\n'))
  elif [[ $uname_str == 'FreeBSD' || $uname_str == 'Darwin' ]]; then
    local env_entries=($(egrep -v '^#' $env_file | xargs -0))
  fi
  IFS=  
 
  # echo "env_entries: ${env_entries[@]}"

  for i in ${!env_entries[@]}; do 
    # echo "${env_entries[i]}"
    local key=$(echo ${env_entries[i]} | cut -d '=' -f 1)
    local value=$(echo ${env_entries[i]} | cut -d '=' -f 2-)
    # echo "$key=$value"
    if (( $i == 0 )); then
      echo -n $value | kubectl -n $NAMESPACE create secret generic $SECRET --dry-run=client --from-file=$key=/dev/stdin -o yaml \
        | kubeseal -o yaml > $sealed_secret_file
    else
      echo -n $value | kubectl -n $NAMESPACE create secret generic $SECRET --dry-run=client --from-file=$key=/dev/stdin -o yaml \
        | kubeseal -o yaml --merge-into $sealed_secret_file  
    fi
  done

  echo "generated sealed secret file: $sealed_secret_file"
}


function unseal() {
  local env_file=$SECRET-secret.env

  kubectl -n $NAMESPACE get secret $SECRET \
    -o template='{{ range $k, $v := .data }}{{ $k }}{{"="}}{{ $v | base64decode }}{{"\n"}}{{end}}' > $env_file

  echo "unsealed secret to file: $env_file"
}


function print_usage() {
  cat <<EOF
usage: $0 command options
  command:
    seal      generate a sealed secret yaml from an .env file.
              a <secret>-sealed-secret.yaml file is generated from a
              <secret>-secret.env file found in the current folder.

    unseal    generate an .env file from an existing k8s secret.
              a <secret>-secret.env is generated where <secret> is an 
              existing secret in a cluster.  

  options:
    --secret|-s     <secret>       name of an new/existing secret
    --namespace|-n  <namespace>    namespace of the above secret

EOF
}


process_args $@
run_command